import json
import os
from datetime import datetime

def generate_test_plan(terraform_plan_path, output_dir):
    """
    Generates a test plan markdown document from a Terraform plan JSON output.

    Args:
        terraform_plan_path (str): The path to the Terraform plan output file (in JSON format).
        output_dir (str): The directory where the test plan will be saved.
    """
    try:
        with open(terraform_plan_path, 'r') as f:
            plan_data = json.load(f)
    except FileNotFoundError:
        print(f"Error: Terraform plan file not found at {terraform_plan_path}")
        return
    except json.JSONDecodeError:
        print(f"Error: Could not decode JSON from {terraform_plan_path}")
        return

    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    timestamp = datetime.now().strftime("%Y-%m-%d")
    output_filename = os.path.join(output_dir, f"test-plan-{timestamp}.md")

    with open(output_filename, 'w') as f:
        f.write(f"# Terraform Deployment Test Plan\n\n")
        f.write(f"**Date Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        f.write(f"**Terraform Plan:** `{os.path.basename(terraform_plan_path)}`\n\n")
        f.write("---\n\n")

        f.write("## Test Cases\n\n")

        f.write("| Test Case ID | Resource Type | Resource Name | Test Steps | Expected Result | Actual Result | Status |\n")
        f.write("|--------------|---------------|---------------|------------|-----------------|---------------|--------|\n")

        test_case_id = 1
        if 'resource_changes' in plan_data:
            for change in plan_data['resource_changes']:
                resource_type = change.get('type', 'N/A')
                resource_name = change.get('name', 'N/A')
                actions = "/".join(change.get('change', {}).get('actions', ['no-op']))

                if 'create' in actions:
                    expected_result = f"Resource `{resource_type}.{resource_name}` should be created and configured correctly."
                elif 'update' in actions:
                    expected_result = f"Resource `{resource_type}.{resource_name}` should be updated successfully."
                elif 'delete' in actions:
                    expected_result = f"Resource `{resource_type}.{resource_name}` should be deleted."
                else:
                    expected_result = "No changes should be applied to this resource."

                test_steps = "1. Run `terraform apply`.\n2. Verify resource in Azure portal."

                f.write(f"| TC-{test_case_id:03d} | `{resource_type}` | `{resource_name}` | {test_steps} | {expected_result} | | Pending |\n")
                test_case_id += 1

    print(f"Test plan successfully generated at: {output_filename}")

if __name__ == "__main__":
    # To use this script:
    # 1. Generate a JSON plan: terraform plan -out=plan.out && terraform show -json plan.out > plan.json
    # 2. Run the script: python src/main.py plan.json
    import sys
    if len(sys.argv) > 1:
        plan_file = sys.argv[1]
        output_directory = "test-plans"
        generate_test_plan(plan_file, output_directory)
    else:
        print("Usage: python src/main.py <path_to_terraform_plan.json>")

