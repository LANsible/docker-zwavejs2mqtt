#######################################################################################################################
# Nexe packaging of binary
#######################################################################################################################
FROM lansible/nexe:4.0.0-rc.2 as builder

# https://github.com/docker/buildx#building-multi-platform-images
ARG TARGETPLATFORM
# https://github.com/zwave-js/zwave-js-ui/releases
ENV VERSION=v8.6.3

# Add unprivileged user
RUN echo "zwave-js-ui:x:1000:1000:zwave-js-ui:/:" > /etc_passwd
# Add to dailout as secondary group (20)
RUN echo "dailout:x:20:zwave-js-ui" > /etc_group

# eudev: needed for udevadm binary
RUN apk --no-cache add \
  eudev

# Setup zwave-js-ui
RUN git clone --depth 1 --single-branch --branch ${VERSION} https://github.com/zwave-js/zwave-js-ui.git /zwave-js-ui

WORKDIR /zwave-js-ui

# Apply stateless patch
COPY stateless.patch /zwave-js-ui/stateless.patch
RUN git apply stateless.patch

# Install all modules
# Run build to make all html files
# https://github.com/zwave-js/zwave-js-ui/blob/master/docker/Dockerfile#L20
RUN CORES=$(grep -c '^processor' /proc/cpuinfo); \
  export MAKEFLAGS="-j$((CORES+1)) -l${CORES}"; \
  yarn install --immutable && \
  yarn build && \
  yarn remove $(cat package.json | jq -r '.devDependencies | keys | join(" ")')

# Remove all unneeded prebuilds
RUN if [ "$TARGETPLATFORM" = "linux/amd64" ]; then \
    export TARGETPLATFORM="linux/x64"; \
  fi && \
  export PLATFORM=${TARGETPLATFORM/\//-}; \
  find . -name *.node -path *prebuilds/* -not -path *${PLATFORM}* -name *.node -delete && \
  find . -name *.glibc.node -path *prebuilds/* -delete

WORKDIR /zwave-js-ui/server

# See: https://github.com/nexe/nexe/issues/441#issuecomment-359654690
RUN sed -i "2s/^/require('ejs');\n/" bin/www.js

# Package the binary
RUN nexe --build \
  --resource hass/ \
  --resource lib/ \
  --resource ../views/ \
  --resource ../dist/ \
  --resource ../node_modules/@esm2cjs \
  --output zwave-js-ui \
  --input bin/www.js && \
  mkdir /config /data

#######################################################################################################################
# Final scratch image
#######################################################################################################################
FROM scratch

# Add description
LABEL org.label-schema.description="Zwave-js-ui as single binary in a scratch container"

# Set env vars for persistance
# https://github.com/zwave-js/zwave-js-ui/blob/master/docs/guide/env-vars.md
# SETTINGS_FILE is from the stateless.patch
# LIBC is set for prebuilify (node-gyp-build) to pickup the bindings file from serialport:
# https://github.com/prebuild/node-gyp-build/blob/2e982977240368f8baed3975a0f3b048999af40e/index.js#L15
ENV TMPDIR=/dev/shm \
  STORE_DIR=/data/ \
  SETTINGS_FILE=/config/settings.json \
  LIBC=musl \
  NO_LOG_COLORS=true

# Copy the unprivileged user
COPY --from=builder /etc_passwd /etc/passwd
COPY --from=builder /etc_group /etc/group

# Serialport is using the udevadm binary
COPY --from=builder /bin/udevadm /bin/udevadm

# Copy needed libs(libstdc++.so, libgcc_s.so) for nodejs since it is partially static
# Copy linker to be able to use them (lib/ld-musl)
# Can't be fullly static since @serialport uses a C++ node addon
# https://github.com/serialport/node-serialport/blob/master/packages/bindings/lib/linux.js#L2
COPY --from=builder /lib/ld-musl-*.so.1 /lib/
COPY --from=builder \
  /usr/lib/libstdc++.so.6 \
  /usr/lib/libgcc_s.so.1 \
  /usr/lib/

# Copy zwave-js-ui binary
COPY --from=builder /zwave-js-ui/server/zwave-js-ui /zwave-js-ui/bin/zwave-js-ui

# Add bindings.node for serialport
COPY --from=builder \
  /zwave-js-ui/node_modules/@serialport/bindings-cpp/prebuilds/ \
  /zwave-js-ui/node_modules/@serialport/bindings-cpp/prebuilds/

# After troubleshooting this somehow can't be packed
COPY --from=builder \
  /zwave-js-ui/node_modules/socket.io-parser/ \
  /zwave-js-ui/node_modules/socket.io-parser/
COPY --from=builder \
  /zwave-js-ui/node_modules/engine.io-parser/ \
  /zwave-js-ui/node_modules/engine.io-parser/
COPY --from=builder \
  /zwave-js-ui/snippets/ \
  /zwave-js-ui/snippets/
COPY --from=builder \
  /zwave-js-ui/node_modules/@zwave-js/config/config/devices \
  /zwave-js-ui/node_modules/@zwave-js/config/config/devices

# Create default data directory
# Will fail at runtime due missing the mkdir binary
COPY --from=builder --chown=zwave-js-ui:0 /config /config
COPY --from=builder --chown=zwave-js-ui:0 /data /data

EXPOSE 8091
USER zwave-js-ui
WORKDIR /zwave-js-ui
# Relative includes so needs to be one folder down from root
ENTRYPOINT ["./bin/zwave-js-ui"]
