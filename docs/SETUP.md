# Setup guide

This takes about 45 minutes the first time. You never create or paste an AWS access key. The only credentials are your own AWS console sign-in (used by CloudShell) and the short-lived OIDC tokens Azure DevOps creates on its own.

Placeholders used below:

| Placeholder | Example | Where it comes from |
|---|---|---|
| `<ado-org>` | `nasimbayati` | The name in `https://dev.azure.com/<ado-org>` |
| `<ado-org-id>` | `1a2b3c4d-...` | Step 2.4 |
| `<ado-project>` | `terraform-aws-platform` | The project you create in step 2.2 |

## 1. AWS: stop using the root user

The root user can do anything, including closing the account, and it cannot be limited by IAM policies. Use it only for account-level tasks.

1. Signed in as root, open **IAM > Users > Create user**. Name it `admin`, tick **Provide user access to the AWS Management Console**, and set a password.
2. Attach the **AdministratorAccess** policy directly.
3. Turn on MFA for the root user (**Security credentials > Assign MFA device**), and later for `admin` too.
4. Sign out, then sign in with the account ID or alias (`nasim-suricata`) as `admin`. Use this user from now on.

## 2. Azure DevOps

1. Go to [dev.azure.com](https://dev.azure.com) and sign in with your Microsoft account. Create an organization if you don't have one. (The Azure portal and Azure DevOps are separate products.)
2. Create a project named `terraform-aws-platform`. Private is fine.
3. Install the free [AWS Toolkit for Azure DevOps](https://marketplace.visualstudio.com/items?itemName=AmazonWebServices.aws-vsts-tools) extension into the organization. Version 1.15.0 or later is needed for OIDC.
4. Find the organization's GUID. Open this URL in the browser where you are signed in:

   `https://dev.azure.com/<ado-org>/_apis/connectionData`

   The `instanceId` field in the JSON is `<ado-org-id>`. If you can't find it, skip ahead: the first pipeline run that tries to reach AWS prints the OIDC issuer URL, which ends with the GUID.

## 3. Bootstrap from AWS CloudShell

CloudShell is a terminal inside the AWS console. It already has the credentials of whoever is signed in, which is why no keys are needed.

1. In the AWS console (signed in as `admin`, region **US East (N. Virginia)**), click the CloudShell icon in the top bar.
2. Install Terraform into your home folder:

   ```bash
   TF=1.16.7
   curl -fsSLO https://releases.hashicorp.com/terraform/$TF/terraform_${TF}_linux_amd64.zip
   mkdir -p ~/bin && unzip -o terraform_${TF}_linux_amd64.zip -d ~/bin && rm terraform_${TF}_linux_amd64.zip
   export PATH=~/bin:$PATH
   # CloudShell's home folder is 1 GB and the AWS provider plugin is several
   # hundred MB, so keep Terraform's working data in /tmp. State files still
   # live in your home folder. After a CloudShell restart, re-run the two
   # export lines and `terraform init`.
   export TF_DATA_DIR=/tmp/tf-bootstrap
   terraform version
   ```

3. Clone the repo and fill in the bootstrap variables:

   ```bash
   git clone https://github.com/nasimbayati/terraform-aws-platform.git
   cd terraform-aws-platform/bootstrap
   cp terraform.tfvars.example terraform.tfvars
   nano terraform.tfvars   # set ado_organization_id, ado_organization_name, ado_project_name
   ```

4. Create the resources:

   ```bash
   terraform init
   terraform plan    # read it: 1 OIDC provider, 2 roles, 1 KMS key, 1 bucket and its settings
   terraform apply
   terraform output
   ```

   Keep the four outputs. You need them in the next steps.

5. Back up the bootstrap state into the bucket it created:

   ```bash
   aws s3 cp terraform.tfstate "s3://$(terraform output -raw state_bucket)/bootstrap/terraform.tfstate"
   ```

## 4. Connect Azure DevOps to AWS

In Azure DevOps, open **Project settings > Service connections > New service connection > AWS**. Create two connections:

| Field | First connection | Second connection |
|---|---|---|
| Access Key ID / Secret | leave empty | leave empty |
| Role to Assume | `plan_role_arn` output | `apply_role_arn` output |
| Role Session Name | `ado-plan` | `ado-apply` |
| Use OIDC | ticked | ticked |
| Service connection name | `aws-plan` | `aws-apply` |

The names must match exactly. The IAM trust policies only accept tokens whose subject is `sc://<ado-org>/<ado-project>/aws-plan` or `.../aws-apply`.

## 5. Variable group, environment and approval

1. **Pipelines > Library > + Variable group**, named `terraform-aws-dev`, with:
   - `BACKEND_BUCKET` = `state_bucket` output
   - `BACKEND_KMS_KEY_ARN` = `state_kms_key_arn` output
   - Optional, only if you turn on the cross-account role: `TF_VAR_cross_account_external_id` with a random value of 16+ characters, marked secret (lock icon).
2. **Pipelines > Environments > New environment**, named `aws-dev`, resource **None**. Open it, then **... > Approvals and checks > Approvals**, and add yourself as the approver.

## 6. Create the pipeline

1. **Pipelines > New pipeline > GitHub (YAML)**. Authorize the Azure Pipelines GitHub App on `terraform-aws-platform` when asked.
2. Choose **Existing Azure Pipelines YAML file**, branch `main`, path `/pipelines/azure-pipelines.yml`, then **Run**.
3. The first run asks you to **Permit** the variable group, the service connections and the environment. Approve each one.
4. When the Apply stage asks for approval, open the Plan stage's Summary tab, read the plan, then approve.

After it finishes, open the AWS console and look at the VPC, the bucket's **Properties > Default encryption**, and **IAM > Roles**.

### No hosted parallelism yet?

If the run fails with "No hosted parallelism has been purchased or granted", the organization needs the free grant of Microsoft-hosted minutes. Request it at <https://aka.ms/azpipelines-parallelism-request>. Approval can take a few business days.

To keep going meanwhile, run a self-hosted agent. The pipeline scripts use bash, so on Windows install the agent inside WSL (Ubuntu): **Project settings > Agent pools > Default > New agent > Linux**, follow the commands, and then change `vmImage: ubuntu-latest` to `name: Default` under `pool:` in `pipelines/azure-pipelines.yml`.

## 7. Show it working

```bash
# Make a branch, change something small, push, open a PR on GitHub
git checkout -b demo/enable-flow-logs
sed -i 's/enable_flow_logs = false/enable_flow_logs = true/' envs/dev/dev.tfvars
git commit -am "Turn on VPC flow logs for rejected traffic"
git push -u origin demo/enable-flow-logs
```

The PR gets a plan with 4 resources to add (log group, IAM role, role policy, flow log). Merge it, approve, and they are created.

## Clean up

See the README's "Tear it down" section. Delete the two service connections afterwards.
