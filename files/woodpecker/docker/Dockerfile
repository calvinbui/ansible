FROM quay.io/woodpeckerci/woodpecker-agent:v3.13.0 AS woodpecker
FROM quay.io/woodpeckerci/plugin-git:2.8.1 AS plugin-git
FROM quay.io/woodpeckerci/plugin-s3:v1.1.0 as plugin-s3
FROM ghcr.io/opentofu/opentofu:1.11.5-minimal AS opentofu
FROM ghcr.io/terraform-linters/tflint:v0.61.0 AS tflint
FROM ghcr.io/aquasecurity/tfsec-scratch:v1.28.14 AS tfsec

FROM public.ecr.aws/docker/library/python:3.14.3-slim

RUN groupadd -g 1000 woodpecker \
  && useradd -m -u 1000 -g 1000 woodpecker \
  && mkdir -p /etc/woodpecker \
  && chown woodpecker:woodpecker /etc/woodpecker

# hadolint ignore=DL3008
RUN apt-get update \
  && apt-get install --yes --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    git-lfs \
    jq \
    libssh-dev \
    rsync \
    ssh \

    # texlive
    fonts-roboto-slab \
    texlive \
    texlive-fonts-extra \
    texlive-xetex \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

COPY requirements.yml .
RUN ANSIBLE_COLLECTIONS_PATH=/usr/share/ansible/collections ansible-galaxy install -r requirements.yml

WORKDIR /usr/local/bin
COPY --from=woodpecker /bin/woodpecker-agent .
COPY --from=plugin-git /bin/plugin-git .
COPY --from=plugin-s3 /bin/plugin-s3 .
COPY --from=opentofu /usr/local/bin/tofu .
COPY --from=tflint /usr/local/bin/tflint .
COPY --from=tfsec /usr/bin/tfsec .
COPY --chmod=0755 mattermost-notify.sh mattermost-notify

USER woodpecker
ENTRYPOINT ["/usr/local/bin/woodpecker-agent"]
