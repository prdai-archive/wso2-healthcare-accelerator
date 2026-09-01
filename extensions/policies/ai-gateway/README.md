# AI Gateway Policies

Reusable policies for the WSO2 API Platform **AI Gateway** (the Go/Envoy-based
gateway). Each policy is a self-contained Python package that a gateway project
pulls in via its `build.yaml`.

## Layout

```
ai-gateway/
└── <policy-dir>/
    ├── policy-definition.yaml   # policy metadata (name, version, parameters)
    ├── pyproject.toml           # pip build config (hatchling)
    ├── requirements.txt         # runtime dependencies
    ├── README.md
    └── src/<module>/
        ├── __init__.py
        └── policy.py            # get_policy(metadata, params) entrypoint
```

The `<policy-dir>` name is arbitrary; the policy's `name` comes from
`policy-definition.yaml`. The `<module>` is the snake_case policy name with a
`_v<major>` suffix (e.g. `pii_masking_openmed_v0`).

## Using a policy

Reference a policy from a gateway project's `build.yaml` with `pipPackage`:

```yaml
version: v1
gateway:
  version: 1.2.1
policies:
  - name: pii-masking-openmed
    pipPackage: github.com/wso2/healthcare-accelerator/extensions/policies/ai-gateway/llm-proxy-pii-masking@v0
```

Then build the image:

```sh
ap gateway image build --name <gateway-name> --path <gateway-project-dir>
```

## Tagging

Policies are versioned by git tag, not by repository release. The
`pipPackage` path is `host/org/repo/<path-to-policy-dir>@v<major>`, and the
builder resolves `@v<major>` to the highest `<path>/v<major>.<minor>.<patch>`
tag in the repository. A policy is only fetchable once its tag exists:

```sh
git tag -a extensions/policies/ai-gateway/<policy-dir>/v0.1.0 -m "<name> policy v0.1.0"
git push origin extensions/policies/ai-gateway/<policy-dir>/v0.1.0
```

On a change, bump the patch/minor version and re-tag.

See [Customizing the Gateway by Adding and Removing Policies](https://github.com/wso2/api-platform/blob/main/docs/cli/customizing-gateway-policies.md) in the API Platform docs.
