FROM alpine:3.19

RUN apk add --no-cache \
    bash sudo curl jq fzf ca-certificates python3 py3-pip \
    libffi openssl tzdata \
  && update-ca-certificates

RUN python3 -m venv /opt/azcli \
 && /opt/azcli/bin/pip install --no-cache-dir --upgrade pip \
 && /opt/azcli/bin/pip install --no-cache-dir azure-cli
ENV PATH=/opt/azcli/bin:$PATH

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=1000
RUN getent group "${USERNAME}" >/dev/null 2>&1 || addgroup -g "${USER_GID}" "${USERNAME}" \
 && getent passwd "${USERNAME}" >/dev/null 2>&1 || adduser -D -u "${USER_UID}" -G "${USERNAME}" -s /bin/bash "${USERNAME}" \
 && echo "%${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
 && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/${USERNAME} \
 && chmod 0440 /etc/sudoers.d/${USERNAME}

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

WORKDIR /workspaces/scripts/azure/portkey

ARG COPY_SCRIPTS=true
COPY scripts/ ./scripts/
RUN if [ "$COPY_SCRIPTS" = "true" ]; then chmod +x ./scripts/*.sh; fi

USER ${USERNAME}

CMD ["bash"]
