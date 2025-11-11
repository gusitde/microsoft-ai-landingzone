# Move to your Terraform project folder
Set-Location "C:\Users\testvmuser\Documents\GitHub\microsoft-ai-landingzone"

# Run Terraform commands step by step
& "C:\tools\terraform\terraform.exe" -version
& "C:\tools\terraform\terraform.exe" init -upgrade
& "C:\tools\terraform\terraform.exe" validate

# Create a binary plan
& "C:\tools\terraform\terraform.exe" plan -out "plan.tfplan"

# Export the plan to JSON
& "C:\tools\terraform\terraform.exe" show -json "plan.tfplan" > "plan.json"

# Optional: Apply the plan
& "C:\tools\terraform\terraform.exe" apply -auto-approve  "plan.tfplan"
