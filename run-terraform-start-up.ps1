# Move to your Terraform project folder
Set-Location "D:\microsoft\GENAI-LandingZone\microsoft-ai-landingzone"

# Run Terraform commands step by step
& "D:\tools\terraform\terraform.exe" -version
& "D:\tools\terraform\terraform.exe" init -upgrade
& "D:\tools\terraform\terraform.exe" validate

# Create a binary plan
& "D:\tools\terraform\terraform.exe" plan -out "plan.tfplan"

# ✅ Export the plan to JSON
& "D:\tools\terraform\terraform.exe" show -json "plan.tfplan" > "plan.json"

# Optional: Apply the plan
& "D:\tools\terraform\terraform.exe" apply -auto-approve  "plan.tfplan"
