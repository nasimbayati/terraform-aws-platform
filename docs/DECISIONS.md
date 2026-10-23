# Design decisions

Each decision lists what was chosen, why, and what it costs. These are the trade-offs worth being able to defend.

## State and locking

**S3 backend with native locking (`use_lockfile = true`), not a DynamoDB table.**
Since Terraform 1.10 the S3 backend can lock by writing a `.tflock` object with an S3 conditional write. The DynamoDB lock table that most tutorials still show is deprecated. One fewer resource, one fewer IAM permission set, same protection: two runs can't write state at the same time.

**The state bucket has its own KMS key, versioning, and `prevent_destroy`.**
State files often hold secrets (generated passwords, connection strings), so they are encrypted with a key only the pipeline roles and admins can use. Versioning means a corrupted state can be rolled back. `prevent_destroy` stops an accidental `terraform destroy` from deleting the one thing you can't rebuild.

**Bootstrap is a separate root module with local state.**
The bucket that stores state, and the roles the pipeline uses, can't be created by that same pipeline. A small bootstrap that a person applies once is the usual answer. Its state is copied into the bucket afterwards as a backup.

**Partial backend configuration (`backend.hcl` / `-backend-config`).**
The backend block can't use variables. Passing bucket and key at `init` keeps account-specific values out of the code and lets another environment reuse the same files.

## Pipeline identity

**OIDC federation instead of access keys.**
Azure DevOps signs a short-lived token for each run. AWS checks the signature against the IAM OIDC provider and the trust policy checks two claims: `aud` must be `api://AzureADTokenExchange`, and `sub` must be `sc://<org>/<project>/<service connection>`. The result is temporary credentials that expire in an hour. There is nothing to rotate and nothing to leak.

**Two roles: read-only for plan, scoped write for apply.**
Plans run on every pull request, including from branches nobody has reviewed yet. With `ReadOnlyAccess`, a malicious change in a PR can't modify the account during `plan`. Only `apply`, which runs on `main` after a human approval, gets write access.

**The apply role is scoped, but not minimal.**
It may use `ec2:*`, `s3:*`, `kms:*` and `logs:*`, and it may only touch IAM roles, policies and instance profiles whose names start with the project prefix. An explicit Deny stops it from editing the pipeline roles or the OIDC provider, which blocks the classic escalation of a pipeline granting itself admin. In production you would narrow the service actions further (for example with IAM Access Analyzer policy generation from CloudTrail) and add a permissions boundary on roles the pipeline creates.

**Apply runs the saved plan artifact.**
`terraform apply tfplan` applies exactly what was reviewed. If the state changed in between, Terraform refuses the stale plan.

## Network

**No NAT Gateway by default.**
A NAT Gateway costs about $32 a month per AZ even when idle. Private subnets reach S3 through a Gateway VPC Endpoint, which is free. A flag adds one NAT Gateway when a workload truly needs internet egress. In production you would use one per AZ so an AZ outage doesn't cut egress for the others.

**Two AZs, /24 subnets on a predictable layout.**
Public subnets are `10.0.0.x/24` and `10.0.1.x/24`, private ones `10.0.10.x/24` and `10.0.11.x/24`, computed with `cidrsubnet`. Leaving gaps makes room for a third tier (for example, data subnets at `10.0.20.0/24`) without re-addressing.

**Default security group emptied, and public subnets don't auto-assign public IPs.**
Both remove ways to expose something by accident.

**App security group: no inbound rules, outbound 443 only to the S3 prefix list.**
Instances are managed through SSM Session Manager, so there is no SSH port to open.

## Storage and encryption

**Customer managed KMS key instead of SSE-S3.**
With a CMK, reading an object needs both S3 permission and KMS permission, so a mistake in one is not enough to expose data. Every decrypt is logged in CloudTrail, and disabling the key makes the data unreadable at once.

**The key policy only delegates to IAM.**
Roles get `kms:Decrypt` from their own IAM policies, with a `kms:ViaService` condition so the key can only be used through S3. This also avoids a dependency loop where the key policy needs a role that needs the key.

**S3 Bucket Keys on.**
S3 asks KMS for a bucket-level key and derives object keys from it, cutting KMS requests (and cost) by up to 99% on busy buckets.

**Bucket policy denies non-TLS requests, uploads that name a different KMS key, and app-role access from outside the VPC endpoint.**
The last condition matches the app role's ARN as a string (`aws:PrincipalArn`), so the bucket can be created before the role exists.

**ACLs disabled (`BucketOwnerEnforced`), Block Public Access on all four settings.**
Access is decided only by policies, which are easier to audit than per-object ACLs.

## IAM patterns

**EC2 role plus instance profile.**
An instance profile is the container that lets EC2 hand a role's temporary credentials to an instance through the metadata service. The app role can only list and read/write the `app/` prefix.

**Cross-account role with an External ID.**
The trust policy names the other account's root (meaning: that account's admins decide which of their principals may assume it), and requires an `sts:ExternalId`. The External ID protects against the confused deputy problem when a third party, such as a SaaS vendor or a data platform, assumes roles for many customers. The same shape is what Databricks Unity Catalog uses for storage credentials on S3.

## Testing and scanning

**`terraform test` with `mock_provider`.**
Tests plan against a fake AWS provider. They check encryption, public access settings, subnet layout, the NAT flag and input validation without an account or any cost.

**checkov fails the build on new findings.**
The accepted findings (no access logging bucket, no cross-region replication, the deploy role's broad service actions) are skipped inline with a `#checkov:skip` comment giving the reason, so every exception is visible in code review.

**Terraform version pinned and checksum-verified in the pipeline.**
Same binary every run, and a tampered download fails the SHA-256 check.
