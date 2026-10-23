# Interview walkthrough

## Two-minute version

> I built a small AWS platform baseline in Terraform and deploy it with Azure DevOps. There's a two-AZ VPC with public and private subnets, where the private subnets have no internet route and reach S3 through a free gateway endpoint. There's an S3 bucket encrypted with a customer managed KMS key, with a bucket policy that enforces TLS, the right key, and VPC-only access for the app role. IAM has an EC2 role with an instance profile scoped to one prefix, and an optional cross-account read-only role protected by an External ID.
>
> State lives in a versioned, KMS-encrypted S3 bucket with S3 native locking, which replaced the old DynamoDB lock table in Terraform 1.10. The pipeline authenticates to AWS with OIDC, so there are no access keys. Pull requests get a plan from a read-only role. On main, the saved plan waits for an approval and then a separate, scoped role applies exactly that plan. Every run also does fmt, validate, offline `terraform test` with a mocked provider, and a checkov scan that fails on new findings.

## Walking through the code (in this order)

1. **`bootstrap/main.tf`**: why it exists (chicken-and-egg), the state bucket hardening, the OIDC provider, and the trust policy conditions on `aud` and `sub`.
2. **`pipelines/azure-pipelines.yml`**: the three stages, the `hasChanges` output variable, the `deployment` job on the `aws-dev` environment, and applying the saved plan.
3. **`modules/network/main.tf`**: subnet math with `cidrsubnet`, the missing NAT and why, the gateway endpoint, the emptied default SG.
4. **`modules/storage/main.tf`**: CMK vs SSE-S3, the three Deny statements in the bucket policy, Bucket Keys.
5. **`modules/iam/main.tf`**: instance profile, `kms:ViaService`, cross-account trust with External ID.
6. **Tests**: `terraform test` with `mock_provider`, and the `expect_failures` test for the External ID rule.

## Questions you will probably get

**What is Terraform state and why keep it remote?**
State maps the resources in your code to real resource IDs in AWS, so Terraform knows what to change. Local state can't be shared, gets lost with a laptop, and has no locking. Remote state in S3 is shared, versioned, encrypted, and locked during writes.

**How does locking work here?**
`use_lockfile = true`. Before a write, Terraform creates `<key>.tflock` in the bucket using a conditional put that fails if the object already exists. A second run sees the lock and waits or fails. Before Terraform 1.10 you needed a DynamoDB table for this, and that option is now deprecated.

**What happens if two engineers run apply at once?**
The second one fails to get the lock. If a run crashes and leaves a lock behind, `terraform force-unlock <id>`, but only after checking that nobody is actually running.

**How does the pipeline get AWS credentials?**
The AWS Toolkit task asks Azure DevOps for an OIDC token for the service connection. The token is signed by `https://vstoken.dev.azure.com/<org-id>`. The task calls `sts:AssumeRoleWithWebIdentity`. AWS checks the signature against the IAM OIDC provider, then the role's trust policy checks that `aud` is `api://AzureADTokenExchange` and `sub` is `sc://<org>/<project>/aws-plan`. AWS returns credentials that last an hour.

**Why two roles?**
Plan runs on unreviewed PRs, so it gets read-only access. Write access only exists after merge and approval.

**What stops the pipeline from making itself an admin?**
The apply role can only touch IAM resources with the project prefix, and an explicit Deny covers the pipeline roles and the OIDC provider. An explicit Deny always wins over an Allow.

**Why a customer managed key and not the default S3 encryption?**
Two independent checks (S3 and KMS) to read data, CloudTrail logs of every decrypt, control over the key policy, and the option to disable the key. The cost is $1 a month per key plus requests, and Bucket Keys cut the request cost.

**What's an instance profile?**
The wrapper that attaches an IAM role to an EC2 instance. The instance gets rotating temporary credentials from the metadata service, so no keys are stored on the server.

**How does cross-account access work?**
Account B's principal calls `sts:AssumeRole` on a role in account A. Account A's trust policy must allow account B, and account B's IAM must allow the principal to call `sts:AssumeRole` on that role ARN. Both sides have to agree. The External ID protects against the confused deputy problem when a vendor serves many customers.

**Gateway endpoint vs PrivateLink?**
Gateway endpoints exist only for S3 and DynamoDB. They are route table entries and are free. Interface endpoints (PrivateLink) put an ENI with a private IP in your subnet, work for most AWS services and for your own services behind an NLB, and cost per hour per AZ plus data. Here the S3 gateway endpoint gives private subnets S3 access without NAT.

**How would you add a prod environment?**
Copy `envs/dev` to `envs/prod` with its own `prod.tfvars` and state key, ideally in a separate AWS account with its own pipeline roles, and add a second environment with stricter approvals. The modules stay the same.

**How would you detect drift?**
A scheduled pipeline run of `terraform plan -detailed-exitcode` that alerts on exit code 2.

**What would you improve?**
Narrow the apply role with IAM Access Analyzer, add a permissions boundary, S3 access logging to a separate log bucket, separate accounts per environment through AWS Organizations, and publish the modules with versions so environments can pin them.

## Being honest about scope

Say it plainly: "This is a personal project in my own account. I built and deployed it to learn Terraform and Azure DevOps properly. I've run the cross-account role by trusting my own account, but I haven't operated cross-account access across an Organization in production." Interviewers respond well to a candidate who knows where their experience ends.

## Demo: cross-account role inside one account

In `envs/dev/dev.tfvars` set `trusted_account_ids = ["<your account id>"]`, add the secret `TF_VAR_cross_account_external_id` to the variable group, and merge. Then in CloudShell:

```bash
ROLE="<cross_account_role_arn from the Apply stage log>"
aws sts assume-role --role-arn "$ROLE" --role-session-name demo --external-id "<the external id>"
# Without --external-id, the same call fails with AccessDenied.
```
