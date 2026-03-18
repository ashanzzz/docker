#!/usr/bin/env sh
set -eu

# Recognize GPU mode may fail if tfjs-node-gpu binding is missing:
#   Error: The Node.js native addon module (tfjs_binding.node) can not be found at path .../tfjs-node-gpu/.../tfjs_binding.node
# This hook ensures the binding exists (fallback: copy the CPU binding) so Recognize won't crash.
# Note: This makes GPU mode functional/stable but may still run on CPU unless a real GPU binding is built.

CPU_BIND="/var/www/html/custom_apps/recognize/node_modules/@tensorflow/tfjs-node/lib/napi-v8/tfjs_binding.node"
GPU_BIND_DIR="/var/www/html/custom_apps/recognize/node_modules/@tensorflow/tfjs-node-gpu/lib/napi-v8"
GPU_BIND="$GPU_BIND_DIR/tfjs_binding.node"

if [ -f "$CPU_BIND" ] && [ ! -f "$GPU_BIND" ]; then
  echo "[recognize] tfjs-node-gpu binding missing; copying CPU binding as fallback" >&2
  mkdir -p "$GPU_BIND_DIR"
  cp -f "$CPU_BIND" "$GPU_BIND"
  # best-effort: chown to www-data (ignore if user/group not found)
  chown www-data:www-data "$GPU_BIND" 2>/dev/null || true
  chmod 755 "$GPU_BIND" 2>/dev/null || true
fi
