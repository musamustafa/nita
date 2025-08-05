# Cisco Nexus EVPN VXLAN Data Centre Example

This example project demonstrates how to use NITA to build and test an EVPN VXLAN leaf‑spine data centre using Cisco Nexus switches.

The structure of this example mirrors the existing Juniper QFX example (`evpn_vxlan_erb_dc`) but is intended for Nexus platforms.  At a minimum it includes:

- An Ansible playbook (`build/sites.yaml`) to build the network using roles designed for Cisco NX‑OS.
- Inventory and variable files under `group_vars` and `host_vars`.
- A `test` directory where Robot Framework tests can be added for validation.

> **Note:** The Nexus‑specific Ansible roles referenced from `sites.yaml` are not yet implemented in this repository.  You should create or import appropriate roles for Nexus (for example `nxos_vxlan_common`, `nxos_vxlan_leaf`, `nxos_vxlan_spine`, etc.) before running the playbook.

To use this example:

1. Copy or create Cisco Nexus–specific roles under your Ansible roles path.
2. Populate `host_vars` and `group_vars` with the IP addresses, credentials and other settings for your environment.
3. Run the build playbook to push the initial configurations:
   ```
   ansible-playbook build/sites.yaml
   ```
4. Add Robot Framework test cases to the `test` directory and execute them using the `robot` command or via NITA's Jenkins integration.

This skeleton is provided as a starting point for building and testing EVPN VXLAN fabrics on Cisco Nexus hardware.
