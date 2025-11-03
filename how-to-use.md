# Plan + export JSONs (no deploy)
.\run-terraform-deploy-and-export.ps1

# Plan + apply + export JSONs (recommended for your “dynamic test plan” and “as-built”)
.\run-terraform-deploy-and-export.ps1 -Apply -AutoApprove

# With workspace and tfvars
.\run-terraform-deploy-and-export.ps1 -Workspace dev -VarFile .\env\dev.tfvars -Apply -AutoApprove
