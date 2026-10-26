# Teardown

Removes everything this project created, in the right order, so nothing is left orphaned. The GitHub repo stays, and you can rebuild in about 15 minutes with [SETUP.md](SETUP.md).

Do not delete things by hand in the console. Deleting the state bucket first makes Terraform lose track of everything else.

## 1. Stop the pipeline from running

Azure DevOps > Pipelines > your pipeline > **⋮** > **Settings** > **Disabled** > Save.

## 2. Destroy the dev environment (AWS CloudShell, N. Virginia)

```bash
export PATH=~/bin:$PATH
cd ~/terraform-aws-platform && git pull
cd envs/dev
export TF_DATA_DIR=/tmp/tf-dev
B=platform-demo-tfstate-207813898654
terraform init \
  -backend-config="bucket=$B" \
  -backend-config="key=envs/dev/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="kms_key_id=$(aws kms describe-key --key-id alias/platform-demo-tfstate --query KeyMetadata.Arn --output text)" \
  -backend-config="dynamodb_table=platform-demo-tflock"
terraform destroy -var-file=dev.tfvars
```

Expect about 30 to destroy. Type `yes`.

## 3. Destroy the bootstrap stack

The state bucket and lock table are protected against accidental deletion, so switch the protection off in your local copy first (this edit is not committed):

```bash
cd ~/terraform-aws-platform/bootstrap
export TF_DATA_DIR=/tmp/tf-bootstrap
sed -i 's/prevent_destroy = true/prevent_destroy = false/' main.tf
sed -i 's/deletion_protection_enabled = true/deletion_protection_enabled = false/' main.tf
sed -i 's/^  bucket = local.state_bucket$/  bucket        = local.state_bucket\n  force_destroy = true/' main.tf
terraform init
terraform apply      # 2 changes: allow bucket and table deletion
terraform destroy    # about 17 to destroy
git checkout main.tf # put the protections back in your local copy
```

KMS keys are not deleted at once: they wait 7 days in "Pending deletion", then AWS removes them.

## 4. Azure DevOps

Project settings > Service connections: delete `aws-plan` and `aws-apply`. The organization and project are free to keep.

## 5. Check

- AWS Billing > Bills: current month should stay at $0.00-$0.xx.
- `aws s3 ls`, VPC console, IAM > Roles: nothing named `platform-demo`.
