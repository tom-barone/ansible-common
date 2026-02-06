# ansible-common

Reusable ansible roles.

# Molecule tests

| Testing Phase | Molecule Action | Purpose |
| --- | --- | --- |
| Environment provisioning | `create` | Provisions test infrastructure and environments |
| Validates ansible syntax without execution | `syntax` | Checks for syntax errors in Ansible playbooks and roles |
| Dependency resolution | `dependency` | Installs required roles, collections, and dependencies |
| Environment preparation | `prepare` | Configures environments before applying automation logic |
| Change application | `converge` | Executes the automation being tested |
| Idempotence verification | `idempotence` | Re-runs automation to verify no unintended changes |
| Side effect detection | `side_effect` | Executes additional automation to test for unintended consequences |
| Functional verification | `verify` | Validates that desired outcomes were achieved |
| Resource cleanup | `cleanup` | Removes temporary files and intermediate artifacts |
| Resource destruction | `destroy` | Cleans up all provisioned resources |
