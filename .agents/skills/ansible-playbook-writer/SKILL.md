---
name: ansible-playbook-writer
description: Creates, edits, or reviews root-level Ansible playbooks (*.yml) for this repository using its naming, Podman, variable, database-role, Ansible Vault, networking, integration, Renovate, and validation conventions. Use whenever asked to add or deploy a service, write a playbook, change a container, add a database, or add an MCP server.
---

# Ansible Playbook Writer

Write playbooks for this repository by copying its established patterns, not by applying generic Ansible preferences.

## Required Research

Before editing:

1. Read `group_vars/all/common.yml` and `roles/podman_container/tasks/main.yml` when their behavior matters.
2. Read the closest existing service playbook and at least two structurally similar playbooks.
3. For MCP services, always read `garmin-mcp.yml`, `home-assistant-mcp.yml`, and the parent service playbook if one exists (`home-assistant-mcp.yml` has `home-assistant.yml`; `garmin-mcp.yml` has no parent).
4. For database-backed services, read the helper role's `defaults/main.yml` and `tasks/main.yml` (`roles/postgres`, `roles/valkey`, …) plus a consumer such as `immich.yml`, `paperless.yml`, or `outline.yml`.
5. Inspect `git status` and preserve unrelated worktree changes.
6. Treat untracked or modified files as candidate work, not as repository precedent.

Do not write a playbook until these checks establish the local convention.

## Repository Shape

- One service = one standalone root playbook. There is no aggregator to register with: `setup-homeserver.yml` is a one-time host bootstrap and `import_playbook` is never used. A new service requires exactly one new file.
- Use `hosts: homeserver` for container services. The inventory's other groups (`octopi`, `nvr`, `nut`, `opnsense`), the implicit `localhost`, and the ad-hoc `borg` group (`setup-borg.yml`, `group_vars/borg/`) are used only for hardware/appliance/host-level playbooks.
- Start every playbook with `---`, a blank line, then the unnamed play (`- hosts: homeserver`); an explanatory file-level comment block between the blank line and the play is established (`bitwarden.yml`, `networking.yml`). Never name plays; `name[play]` is deliberately in the `.ansible-lint` skip_list.
- Separate tasks with exactly one blank line; a task's comment sits directly above its `- name:`. Two-space indent, no tabs. Long lines are fine — line-length is disabled; never wrap an inline quoted Jinja expression mid-string to satisfy line length. For a genuinely long expression, the established idiom is a `>-`/`|-` block scalar with the `{{ … }}` spread over multiple lines (`woodpecker.yml`, `ntp.yml`, `crowdsec.yml`, `garmin-mcp.yml`).
- Pushing to master deploys: Woodpecker CI lints every changed root playbook on push and executes changed playbooks on master.

## Naming

- Put service playbooks at the repository root as `<application>.yml`, lowercase kebab-case. Three legacy exceptions (`acme.sh.yml`, `blackbox_exporter.yml`, `systemd_exporter.yml`) are not precedent; do not imitate or rename them.
- Set `application` to the filename stem for a normal single-service playbook. It drives `config_directory`, the default container name, the hostname/DNS name, and generated integration labels. Multi-play files (`email-backup.yml`), multi-instance files (`sonarr.yml` — one play instantiating the sonarr role twice, as `sonarr` and `sonarr-anime`), and deployment-named files (`nut-server.yml` → `application: nut`) legitimately diverge.
- Omit `container_name` for the main container — the role defaults both name and hostname to `application`. Do not copy the redundant `container_name: "{{ application }}"` in `garmin-mcp.yml` and `home-assistant-mcp.yml`; set it only when the name must differ from `application`.
- Name sidecars `{{ application }}-<component>` (`immich.yml`, `paperless.yml`, `nextcloud.yml`, `librechat.yml`). In some multi-container stacks every container takes a suffix, including the primary (`immich-server`, `woodpecker-server`, `obico-web`). Well-known standalone upstream projects may keep their upstream names (`home-assistant.yml` runs `eufy-security-ws`, `govee2mqtt`, `wyoming-piper`).
- Database sidecars are named by the helper roles' defaults (`{{ application }}-postgres` and so on) — set `<prefix>_name` manually only for a second instance of the same database in one play, as `librechat.yml` does with `valkey_name`/`postgres_name` for its firecrawl instances.
- Name a companion MCP service `<service>-mcp` (`home-assistant-mcp.yml` with `application: home-assistant-mcp`); the parent need not be a repo playbook (`garmin-mcp`).
- The container name is the DNS name other containers reference (for example LibreChat `allowedAddresses` entries such as `garmin-mcp:8000`).

## Play Variables

The normal container-service play `vars` block contains only:

```yaml
vars:
  application: example

  container_network: "{{ networks.pub }}"
```

- Put `application` first and `container_network` last, separated by a blank line, with justified extra vars between them. Two tracked files deviate (`home-assistant.yml`, `thanos.yml` define extras after `container_network`) — treat them as legacy, not precedent to copy.
- Put one-use container configuration directly under the `include_role` task's `vars` or `env` mapping.
- Promote a value to a play variable only when it is reused, transformed, consumed by multiple tasks, or referenced from a `files/<application>/` template or mid-string inside a larger Jinja expression — an inline `!vault` block cannot appear in either place (`authelia.yml`, `hauk.yml`, `tracearr.yml`). Never leave a play variable with no consumer.
- Play-level overrides of globals are precedented where genuinely needed (`borgmatic.yml` overrides `config_directory`; `setup-borg.yml` overrides `common_user`).
- Prefix internal facts and registers with `_`; name one-off command registers `_command_result`. Facts deliberately shared across plays via `hostvars` are unprefixed (`woodpecker.yml`). Add `no_log: true` when a fact holds credentials.
- Do not introduce environment lookups, `vars_prompt`, `assert` tasks, or `mandatory` filters unless the user explicitly requests them; the sole tracked use is `woodpecker.yml`'s vault-password fallback.

## Secrets

- Put a one-use secret directly at its point of consumption as an inline `!vault` value:

```yaml
env:
  SERVICE_URL: "http://service:8080"
  SERVICE_TOKEN: !vault |
    $ANSIBLE_VAULT;1.1;AES256
    ...real ciphertext created from the real value...
```

- Host a secret in `group_vars/all/` when it is consumed by more than one playbook, a `files/` template of another service, or a role (`common_email_password`, `openai_api_key`, `shlink_api_key` via `files/privatebin/conf.php.j2`) — or when it belongs in an existing themed group_vars file next to sibling secrets (`bazarr_api_key` in `usenet_common.yml`). Otherwise keep it inline.
- OIDC client secrets are never inline: add an `oidc_auth.<application>` entry (`redirect_uris` plus vaulted `secret`) to `group_vars/all/oidc.yml`; Authelia consumes the whole mapping via `files/authelia/configuration.yml.j2`. The generation command is documented at the top of `oidc.yml`.
- Use YAML anchors when one vaulted value is reused within a single playbook: declare an anchor named for the credential — `&<provider>_<field>`, optionally `_`-prefixed (`&frugal_username`, `&github_token`, `&_woodpecker_agent_secret`) — on the first occurrence and alias it later (`nzbget.yml`, `renovate.yml`, `jdownloader.yml`, `woodpecker.yml`). Do not add an anchor that is never aliased.
- Hashing a real credential into the stored format an app requires (bcrypt `password_hash`, SHA512 passwd lines, digest-auth HA1) is normal — `ntfy.yml`, `syncthing.yml`, `email-backup.yml`, `shelly-gen2.yml`.
- Never derive a new credential by hashing or reusing another secret, and never hash an existing secret to avoid asking the user for a real value — generate an independent value and vault it instead. The one tracked derivation (SearXNG's `secret_key` in `librechat.yml` hashing the OIDC secret) is a known wart, not precedent to copy.
- Never commit an encrypted placeholder, empty vault, `changeme`, or fabricated credential. Never invent a secret value.
- If a required secret is unavailable, stop and ask the user for the real value before creating its vault block.
- `ansible.cfg` points `vault_password_file` at `~/.vault_pass.txt`, so `ansible-vault encrypt_string` works from the repo root without prompting. Never expose plaintext in a file or final response.

## Databases

- Create databases only through the helper roles (`postgres`, `valkey`, `mongodb`, `influxdb`, `elasticsearch`, `meilisearch`) in a task named `Create <db> container` placed before the app's `Create container` task. Never build a database with `podman_container` directly. Prefer postgres for new SQL services; the `mariadb` role has zero consumers.

```yaml
- name: Create postgres container
  ansible.builtin.include_role:
    name: postgres
  vars:
    postgres_version: 18.4
    postgres_password: !vault |
      $ANSIBLE_VAULT;1.1;AES256
      ...real ciphertext...
```

- Pass only `<prefix>_version` and an inline-vaulted `<prefix>_password` in the common case. The role names the container, user, database, and data directory from `application`; override only for a concrete need (a postgres derivative image such as postgis/vectorchord/timescaledb, or a second instance in the same play as in `librechat.yml`).
- Write the version as an unquoted literal copied from a neighbouring playbook. Renovate customManagers match the exact `<prefix>_version: ` string — Jinja, quotes, or a v-prefix silently break updates. `meilisearch_version` and nonstandard postgres pins are not covered; a custom postgres image needs its own customManagers pair in `renovate.json5` (copy the immich/tracearr/librechat entries, commit as `renovate: <change>`).
- Consume connection details only via the `_`-prefixed facts the roles export: `_postgres_hostname/_port/_username/_password/_database`, `_postgres_url`/`_postgresql_url`, `_valkey_url`, `_mongo_url`, `_elasticsearch_url`, `_meilisearch_url` plus `_meilisearch_password`. Never hardcode `{{ application }}-postgres` hostnames or repeat the vaulted password in `env`. The mongodb role uses `mongo_*` vars and `_mongo_*` facts, not `mongodb_*`.
- Use the URL fact when the app takes a connection string (`DATABASE_URL: "{{ _postgres_url }}"` in `outline.yml`, `umami.yml`); discrete facts otherwise (`immich.yml`). Cast port facts: `"{{ _postgres_port | ansible.builtin.string }}"`.
- Never pass `requires` for role-created databases: `podman_container` auto-adds them for default-named postgres/valkey/mariadb/mongodb/influxdb/elasticsearch sidecars, and precedent adds none for the remaining cases (meilisearch and renamed second instances get no requires at all).
- Do not add wait/pause tasks for database readiness — the postgres and mariadb roles pause internally after (re)creating their container, and no playbook waits on the other database roles.

## Task Structure

- Keep ordinary services as root playbooks. The only service role, `roles/sonarr`, exists because `sonarr.yml` instantiates it twice (sonarr and sonarr-anime); create a role only for that multi-instance case.
- Canonical task order: create folders → database roles → write config files (`notify: Restart`) → `Create container` → post-start `containers.podman.podman_container_exec` tasks. A config file may precede the database roles only when it references none of their `_`-prefixed facts; any file templating `_postgres_*`/`_valkey_*` facts must come after the roles that export them (`authelia.yml`, `grafana.yml`, `immich.yml`).
- Name the primary directory task `Create config folder` whether or not it loops over several paths (`librechat.yml`, `home-assistant-mcp.yml` loop under the singular name); the plural `Create config folders` is a tolerated minority variant. Give additional directories short descriptive names in the same style (`Create tokens folder`).
- Do not create directories for stateless services — the smallest playbooks (`it-tools.yml`, `flaresolverr.yml`, `dozzle.yml`, `whodb.yml`) have no file tasks at all.
- Store config and application state beneath `{{ config_directory }}`. Mount bulk or shared data — media, photos, downloads, backups — from the shared `common_directory_*` variables, as `plex.yml` and `immich.yml` do.
- Match directory owner/group to the image runtime UID/GID and the nearest comparable playbook. Do not guess between `common_user`/`common_group`, `common_user_id`/`common_group_id`, `common_root_id`/`common_root_group`, literal `root`, or image-specific UIDs such as `"65534"` — copy the exact pair from precedent.
- Quote modes: `"0771"` for directories, `"0644"` for files, `"0600"` for secrets.
- Create application containers through the `podman_container` role; name the task `Create container` and sidecar tasks `Create <component> container` (MCP playbooks use `Create MCP server` or `Create container`):

```yaml
- name: Create container
  ansible.builtin.include_role:
    name: podman_container
  vars:
    image: registry.example/image:1.2.3
```

- Do not duplicate defaults the role already provides (network, timezone, container name/hostname) without a concrete reason.
- Never pass `requires` for database sidecars, and note that no tracked playbook passes explicit `requires` at all; reserve it for a genuine cross-playbook startup dependency.
- Healthchecks are opt-in and rare: pass the flat `healthcheck*` vars only where precedent demands (`prowlarr.yml`, `radarr.yml`); use `no_healthcheck: true` to silence a noisy image-defined healthcheck (`authelia.yml`, `homepage.yml`).

## Config Files And Handlers

- When the playbook writes config a running container consumes, define the play handler between `vars` and `tasks`:

```yaml
handlers:
  - name: Restart
    containers.podman.podman_container:
      name: "{{ application }}"
      force_restart: true
```

- Attach `notify: Restart` (string form, not a list) to every template/copy/lineinfile task whose output the container reads. Name sidecar handlers `Restart <component>` and notify them from the sidecar's config task (`paperless.yml`).
- The direct `containers.podman.podman_container` module appears only in restart handlers (plus `qbittorrent.yml`'s stop-before-edit); use `containers.podman.podman_container_exec` for in-container commands (`nextcloud.yml`, `forgejo.yml`).
- Repo-managed config sources live in `files/<application>/`, referenced via `{{ files_directory }}` — never a hardcoded path. Jinja-templated files keep the real target filename plus a `.j2` suffix and deploy with `ansible.builtin.template` to `{{ config_directory }}/<name-without-.j2>`; verbatim assets carry no suffix and use `ansible.builtin.copy`.
- For a single small generated file, prefer `ansible.builtin.copy` with an inline `content: |` block — Jinja renders inside it (`grafana.yml`, `librechat.yml`); reserve `files/<application>/*.j2` for multi-file or long configs.
- Use `lineinfile`/`blockinfile` only to surgically patch files the application itself owns and rewrites (`nzbget.yml`, `home-assistant.yml`, `paperless.yml`), typically a `dict2items` loop with `regexp: "^{{ item.key }}="` and `notify: Restart`. Never use them to build a repo-managed config.
- Schedule recurring in-container jobs with `ofelia.*` labels on the target container (`nextcloud.yml`, `renovate.yml`, `crowdsec.yml`), never host cron; the ofelia daemon discovers labels via the podman socket, so `ofelia.yml` needs no change.
- Backups are path-based: everything under `/apps` (where `{{ config_directory }}` lives) is backed up nightly by the borgmatic apps job. Never edit `borgmatic.yml` for a new service; at most add cache or rebuildable paths to the apps job's `exclude_patterns` in `group_vars/all/borgbackup.yml`, written from the container-side root (`/mnt/source/<application>/...`).

## Images, Environment, And Renovate

- Write every image as a plain single-token literal — `image: <registry-host>/<path>:<tag>` — unquoted, with no Jinja and no YAML anchor. Renovate scans every YAML file but only matches literal values: the anchored images in `thanos.yml` and `drawio.yml` have not received an update since they were anchored. When several containers share an image, repeat the literal line verbatim; Renovate bumps all occurrences in one commit (`dawarich.yml`).
- Always include the registry host — the string as written becomes Renovate's depName and commit-message prefix. Preserve the upstream tag style exactly (keep the `v` prefix only where upstream uses it).
- Locally built images are `localhost/{{ application }}:latest` (`garmin-mcp.yml`) — or `localhost/{{ application }}-<component>:latest` per built component in a multi-image stack (`obico.yml`) — or the `podman_image` build name (`woodpecker.yml`); never digest-pin them.
- When upstream publishes only a floating tag, digest-pin it as `<tag>@sha256:<hex>` (`traefik.yml`, `node-exporter.yml`, `wakeupbr.yml`) so Renovate issues digest updates; some tracked images keep a bare floating tag — match the nearest precedent.
- A suffixed or nonstandard tag scheme (`version-…`, `1.7.2-apache`, `ubuntu-…-full`) needs a matching versioning entry in `renovate.json5` `packageRules` — check for one and add it in the same change.
- Pin `ansible.builtin.git` checkouts with `version:` set to a bare release tag when updates matter — a customManagers regex renovates exactly that shape (`acme.sh.yml`, `borgmatic.yml`); a branch name opts out.
- Define `env` as a mapping and group related settings with blank lines.
- Quote Jinja-only values. Stringify IDs with `"{{ common_user_id | ansible.builtin.string }}"`, quote plain numeric literals (`"4"`), and write booleans as strings matching the casing the app expects (`"true"`, or `"True"` for Django-style images).
- The role already passes `timezone: common_timezone` to every container; add `TZ` only for images that read the env var (linuxserver.io and similar), always as `TZ: "{{ common_timezone }}"`, never a hardcoded zone.
- Env-block anchors are fine for genuinely repeated blocks (`obico.yml` `&web_env`) — but never anchor an image line.

## Storage And Networks

- Express bind mounts as strings under `volumes`; add `:ro` when the container does not need write access. No named volumes exist anywhere — do not introduce one.
- Never publish host ports — no playbook does, and the role does not pass `publish`/`ports` to podman; `exposed_ports` is likewise unused. All networks are macvlan VLANs, so every container has its own routable IP.
- Choose the network by role, matching the closest precedent: `networks.pub` for ordinary web services behind Traefik (the default); `networks.iot` for home-automation and device-facing services (`home-assistant.yml`, `zigbee2mqtt.yml`, `adguard.yml`, `home-assistant-mcp.yml`); `networks.user` for LAN-user-facing infrastructure and monitoring (`prometheus.yml`, `grafana.yml`, `samba.yml`); `networks.mgmt` for network management (`traefik.yml`, `unifi.yml`); `networks.guest` for internet-only egress jobs (`ddns-updater.yml`, `fitbit-activity-generator.yml`). No container playbook uses `lan`, `wan`, or vpn networks.
- Pass only `container_network` for the normal single-network case. For multi-network attachment, override the role's `network:` var with a list of `{name, ip}` dicts while still setting `container_network` to the primary network (`netbootxyz.yml`, `wakeupbr.yml`, `watchyourlan.yml`), and hand-add a `traefik.docker.network={{ container_network.name }}` label if the service is Traefik-routed.
- Add a fixed `ip` only when a service must be directly reachable on the LAN (DNS, MQTT, PXE, auth portal, casting). The idiom is `ip: "{{ container_network.subnet | ansible.utils.nthhost(N) }}"` with N below the network's `dhcp_pool.start` and unique on that network; setting `ip` also creates an OPNsense DHCP/DNS reservation and firewall alias via the role.
- Use the role's `tmpfs` mapping for scratch paths (`/path: rw,mode=01777`) instead of bind mounts (`plex.yml`, `unifi.yml`, `seerr.yml`).

## Integrations

Add `traefik`, `homepage`, `blackbox`, or `metrics` under the `include_role` vars only when the service needs them and comparable playbooks agree. Internal sidecars and MCP servers get none; user-facing web UIs almost always get `traefik` plus `homepage`. Omitting `traefik` is sufficient to keep a service private — the role stamps `traefik.enable=false` on its own. Never hand-build labels the role generates from these vars.

**Traefik** — a LIST of route dicts; `port` is the only required field:

```yaml
traefik:
  - port: 8080
    auth: page
```

- `auth: page` (the only auth value used) adds Authelia forward-auth — use it for UIs that need SSO gating.
- Omit `rule` when it would equal the default ``Host(`<application>.<common_tld>`)``; write it only for genuinely custom hosts or matchers (`PathPrefix`, `Header`).
- `name` only for a second route or non-default host; the conventional second route is `{{ application }}-bypass-auth` with a `Header(...)` rule (`qbittorrent.yml`).
- `middlewares` is plural and a YAML list (`nextcloud.yml`, `euro-office.yml`); singular `middleware:` is silently ignored — do not copy `calibre-web.yml`.
- `type: udp` or `type: tcp` for non-HTTP services (`ntp.yml`). Do not invent other fields: no playbook overrides entrypoints, tls, certresolver, or priority.

**Homepage** — a DICT. Adding it requires exactly one icon file at `files/homepage/icons/<application>.(png|svg|jpg|jpeg|webp)` or the play hard-fails; the only alternative is an explicit `icon:` referencing an existing icon (`ownfoil.yml`):

```yaml
homepage:
  group: Tools
  weight: 500
  description: "What it does"
```

- `group`, `weight`, and `description` always; add `name` only when the auto title-cased application is wrong as a display name (`Actual Budget`); add `href` only when the default `https://<application>.<common_tld>` is wrong.
- Pick `group` from the existing set (Favourites, Tools, Monitoring, Networking, Sharing, Programming, Media, Documents, Home Automation, Management, Backups, Plex, 3D Printing, Storage, Collaboration, Gaming, Remote Access, Home) rather than inventing a new one.
- `widget` is a dict: omit `type` when the gethomepage slug equals `application`; put credentials inline (`key: !vault |` or a shared var like `{{ plex_token }}`); write multi-value `fields` as a JSON array inside a YAML string: `fields: '["photos", "videos"]'`.
- Homepage restarts are handled inside the role — never add a homepage restart notify from a playbook.

**Blackbox** — automatic for every Traefik-routed service whose first route is HTTP or TCP (the role probes the first route; a `type: udp` first route such as `ntp.yml`'s gets no probe). Write a DICT only to customize: `path: /health` to aim the probe at a health endpoint (the dominant customization), `enable: false` to opt out, or `protocol: http` plus `host:` for internal targets (`adguard.yml`). It is a dict, not a list — `euro-office.yml`'s list form is silently ignored; do not copy it.

**Metrics** — exporter/monitoring playbooks only (`node-exporter.yml`, `nut-exporter.yml`); a list of `{port[, path]}` dicts. Do not add it to ordinary application services.

**Hand-built `labels`** — a list of `"key=value"` strings, only for label types the role does not generate: `com.centurylinklabs.watchtower.enable=false` (watchtower generation is commented out of the role), `ofelia.*` job labels, Traefik middleware definitions, and `traefik.docker.network` on multi-network containers.

**LibreChat MCP wiring**:

- For a new MCP service, add only its exact `host:port` to `mcpSettings.allowedAddresses` in `librechat.yml` — this alone sufficed for `garmin-mcp` and `home-assistant-mcp` — unless the user explicitly asks for a centrally configured `mcpServers` entry.
- Do not modify companion playbooks merely because an integration might be useful. Keep the requested change minimal and preserve unrelated changes in files such as `librechat.yml`.

## Minimal Template

Use this only after adapting it to the nearest tracked examples. The smallest real playbooks (`it-tools.yml`, `whodb.yml`, `flaresolverr.yml`, `dozzle.yml`) are exactly a vars block plus one `Create container` task:

```yaml
---

- hosts: homeserver

  vars:
    application: example

    container_network: "{{ networks.pub }}"

  tasks:
    - name: Create container
      ansible.builtin.include_role:
        name: podman_container
      vars:
        image: registry.example/example:1.2.3
        env:
          EXAMPLE_SETTING: value
        traefik:
          - port: 8080
        homepage:
          group: Tools
          weight: 500
          description: "What it does"
```

- Drop `traefik`/`homepage` for internal-only services and MCP servers; remember `homepage:` needs the icon file first.
- Only for services with persistent state, add before the container task (owner/group per the image runtime):

```yaml
    - name: Create config folder
      ansible.builtin.file:
        path: "{{ config_directory }}"
        state: directory
        owner: "{{ common_user }}"
        group: "{{ common_group }}"
        mode: "0771"
```

  and mount it: `volumes: ["{{ config_directory }}:/data"]` (written in list-string form).

The smallest playbook matching repository precedent is preferred.

## Validation

Run from the repository root — `ansible.cfg`, `.ansible-lint`, and `.yamllint` are discovered from cwd, and `~/.vault_pass.txt` must exist (both ansible-playbook and ansible-lint fail hard without it):

```bash
ansible-playbook <playbook>.yml --syntax-check   # parse-only: does not decrypt vault or resolve variables
ansible-lint <playbook>.yml                      # the real gate (profile production; enable_list includes yaml, subsuming yamllint)
yamllint <playbook>.yml                          # fast pre-check, needs no vault
git diff --check -- <changed-files>              # tracked, unstaged changes only — for a NEW file: git add first, then git diff --check --cached
```

- A clean ansible-lint run ends with `Profile 'production' was required, and it passed.`
- `librechat.yml` has pre-existing `yaml[trailing-spaces]` failures at HEAD — do not fix or report those as part of an unrelated change, and do not claim full validation while unrelated pre-existing failures remain.
- Respect the `.ansible-lint` skip_list: unnamed plays, unprefixed role vars, `when: <register>.changed` instead of handlers, Jinja in task names, and unpinned git clones are deliberate idioms — do not "fix" them.
- Passing lint does not guarantee runtime success: CI executes changed playbooks on master, so a runtime failure breaks the deploy.
- When changing a companion playbook such as `librechat.yml`, syntax-check it too.

## Committing

- Do not commit or push unless asked — pushing to master deploys via CI.
- Message format: `<application>: <lowercase imperative summary>` (`librechat: add gpt-5.6-sol`); use `renovate: <change>` for `renovate.json5` changes. Version and digest bumps belong to Renovate — never hand-bump a properly formatted pin; formatting the pin correctly is the whole job.

## Final Checklist

Before finishing, confirm:

- Filename and `application` match; the play was based on tracked neighboring examples.
- Play vars: `application` first, `container_network` last; every extra play variable has a consumer.
- One-use secrets are real inline vault values at their use site; shared secrets live in `group_vars` (OIDC in `oidc_auth`); nothing placeholder, fabricated, or derived from another secret.
- Databases go through the helper roles and are consumed via `_`-prefixed facts; version pins are unquoted literals Renovate can match.
- Main container creation uses `podman_container`; the image is a registry-qualified pinned literal (no anchor, no Jinja).
- Config-file tasks `notify: Restart` and the handler exists; `homepage:` only with its icon file in place; integration payloads match the shapes above.
- No unnecessary directory, port, variable, route, label, helper, or integration was added.
- Unrelated worktree changes were preserved.
- Syntax, lint, YAML, and whitespace validation passed for the changed files.
