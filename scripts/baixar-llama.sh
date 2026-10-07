#!/bin/bash
# Baixa o llama.cpp já compilado para Apple (xcframework oficial das Releases) para vendor-llm/.
# É o motor que roda os modelos de linguagem (.gguf) no iPhone, com a GPU (Metal).
# Roda no GitHub Actions (macOS).
set -euo pipefail

# Versão fixada: a ponte em App/Motor/MotorLLM.c foi escrita para a API desta época.
TAG=b11435
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$RAIZ/vendor-llm"
OBRA="$RAIZ/build-llm"

if [ -d "$DEST/llama.xcframework" ] && ls -d "$DEST"/llama.xcframework/ios-arm64* >/dev/null 2>&1; then
  echo "llama.xcframework já baixado (cache)"; exit 0
fi

rm -rf "$OBRA" "$DEST"; mkdir -p "$OBRA" "$DEST"
cd "$OBRA"
URL="https://github.com/ggml-org/llama.cpp/releases/download/$TAG/llama-$TAG-xcframework.zip"
if ! curl -fsSL --retry 3 -o llama.zip "$URL"; then
  echo "::warning::não achei a versão $TAG; usando a mais nova das Releases"
  URL="$(curl -fsSL https://api.github.com/repos/ggml-org/llama.cpp/releases/latest \
        | grep -o 'https://[^"]*xcframework\.zip' | head -1)"
  [ -n "$URL" ] || { echo "::error::não achei o xcframework do llama.cpp nas Releases"; exit 1; }
  echo "baixando $URL"
  curl -fsSL --retry 3 -o llama.zip "$URL"
fi
unzip -q llama.zip
X="$(find . -type d -name 'llama.xcframework' | head -1)"
[ -n "$X" ] || { echo "::error::o zip não trouxe llama.xcframework"; find . -maxdepth 3; exit 1; }
mv "$X" "$DEST/llama.xcframework"

echo "fatias:"; ls "$DEST/llama.xcframework"
ls -d "$DEST"/llama.xcframework/ios-arm64* >/dev/null 2>&1 \
  || { echo "::error::o xcframework não tem a fatia de iPhone (ios-arm64)"; exit 1; }
H="$(find "$DEST/llama.xcframework" -path '*ios-arm64/*' -name llama.h | head -1)"
[ -n "$H" ] || { echo "::error::faltou o cabeçalho llama.h na fatia de iPhone"; exit 1; }
# funções que a ponte usa: se alguma sumiu nesta versão, avisa aqui em vez de falhar no meio do Xcode
for f in llama_model_load_from_file llama_init_from_model llama_model_get_vocab llama_vocab_is_eog \
         llama_chat_apply_template llama_model_chat_template llama_sampler_chain_init llama_batch_get_one; do
  grep -q "$f" "$H" || { echo "::error::esta versão do llama.cpp não tem $f (a ponte MotorLLM.c precisa ser ajustada)"; exit 1; }
done
du -sh "$DEST/llama.xcframework"
