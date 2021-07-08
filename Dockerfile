#######################################################################################################################
# Nexe packaging of binary
#######################################################################################################################
FROM lansible/nexe:4.0.0-beta.18 as builder

ENV VERSION=v5.2.1

# Add unprivileged user
RUN echo "zwavejs2mqtt:x:1000:1000:zwavejs2mqtt:/:" > /etc_passwd
# Add to dailout as secondary group (20)
RUN echo "dailout:x:20:zwavejs2mqtt" > /etc_group

# eudev: needed for udevadm binary
RUN apk --no-cache add \
  eudev

# Setup zwavejs2mqtt
RUN git clone --depth 1 --single-branch --branch ${VERSION} https://github.com/zwave-js/zwavejs2mqtt.git /zwavejs2mqtt

WORKDIR /zwavejs2mqtt

# Apply stateless patch
COPY stateless.patch /zwavejs2mqtt/stateless.patch
RUN git apply stateless.patch

# Install all modules
# Run build to make all html files
RUN CORES=$(grep -c '^processor' /proc/cpuinfo); \
  export MAKEFLAGS="-j$((CORES+1)) -l${CORES}"; \
  npm install && \
  npm run build && \
  npm prune --production

WORKDIR /zwavejs2mqtt/server

# See: https://github.com/nexe/nexe/issues/441#issuecomment-359654690
RUN sed -i "2s/^/require('ejs');\n/" bin/www.js

# Package the binary
RUN nexe --build \
  --resource hass/ \
  --resource lib/ \
  --resource ../views/ \
  --resource ../dist/static \
  --output zwavejs2mqtt \
  --input bin/www.js && \
  mkdir /config /data


#######################################################################################################################
# Final scratch image
#######################################################################################################################
FROM scratch

# Add description
LABEL org.label-schema.description="Zwavejs2mqtt as single binary in a scratch container"

# Set env vars for persistance
# https://github.com/zwave-js/zwavejs2mqtt/blob/master/docs/guide/env-vars.md
# SETTINGS_FILE is from the stateless.patch
ENV STORE_DIR=/data/ \
  ZWAVEJS_EXTERNAL_CONFIG=/data/ \
  SETTINGS_FILE=/config/settings.json

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

# Copy zwavejs2mqtt binary
COPY --from=builder /zwavejs2mqtt/server/zwavejs2mqtt /zwavejs2mqtt/bin/zwavejs2mqtt

# Add bindings.node for serialport
COPY --from=builder \
  /zwavejs2mqtt/node_modules/@serialport/bindings/build/Release/bindings.node \
  /zwavejs2mqtt/build/bindings.node

# Add files needed, doesn't work as --resource
COPY --from=builder \
  /zwavejs2mqtt/node_modules/@serialport/bindings/lib/linux.js \
  /zwavejs2mqtt/node_modules/@serialport/bindings/lib/linux.js

# https://github.com/zwave-js/node-zwave-js/tree/master/packages/config/config
COPY --from=builder \
  /zwavejs2mqtt/node_modules/@zwave-js/config/config/ \
  /zwavejs2mqtt/node_modules/@zwave-js/config/config/

# Create default data directory
# Will fail at runtime due missing the mkdir binary
COPY --from=builder --chown=zwavejs2mqtt:0 /config /config
COPY --from=builder --chown=zwavejs2mqtt:0 /data /data

EXPOSE 8091
USER zwavejs2mqtt
WORKDIR /zwavejs2mqtt
# Relative includes so needs to be one folder down from root
ENTRYPOINT ["./bin/zwavejs2mqtt"]
