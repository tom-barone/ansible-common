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

## Molecule development tips

Use this task in a playbook to pause execution and allow for manual verification of the container state during testing:

```yaml
- name: Infinite sleep to allow manual verification
  # When this runs, you can do `docker exec -it <container_name> bash`
  # to get a shell in the container at this point and verify the
  # state of the system manually.
  ansible.builtin.command: sleep infinity
  async: 0
  poll: 0
```
