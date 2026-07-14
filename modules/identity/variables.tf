variable "prefix" {
  type = string
}

variable "root_management_group_id" {
  type = string
}

variable "rbac_groups" {
  description = "Map of persona => { display_name, description, role, scope }."
  type = map(object({
    display_name = string
    description  = string
    role         = string
    scope        = string
  }))
  default = {}
}

variable "github_repository" {
  description = "GitHub org/repo for OIDC federation, e.g. RajeshPat87/azure-landing-zone-platform."
  type        = string
}

variable "github_environments" {
  description = "GitHub environment names allowed to federate."
  type        = list(string)
  default     = ["plan", "apply"]
}

variable "cicd_role" {
  description = "Role granted to the CI/CD identity at root MG scope."
  type        = string
  default     = "Contributor"
}
