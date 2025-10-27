#TODO: determine what a good set of outpus should be and update.
output "resource_id" {
  description = "Future resource ID output for the LZA."
  value       = "tbd"
}

output "naming_genai_key_vault_name" {
  description = "Generated Key Vault name for verification"
  value       = module.naming_genai_key_vault.name
}

output "naming_foundry_account_name" {
  description = "Generated AI Foundry account name for verification"
  value       = module.naming_ai_foundry_account.name
}

output "naming_genai_cosmos_account_name" {
  description = "Generated Cosmos DB account name for verification"
  value       = module.naming_genai_cosmos_account.name
}

output "naming_apim_name" {
  description = "Generated API Management service name for verification"
  value       = module.naming_apim.name
}
