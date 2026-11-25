#!/usr/bin/env bash
# 在持有人自己的终端核对签名材料；不输出或保存解密后的私钥。
set -euo pipefail
p12="${1:?签名 p12 的实际文件路径}"
p8="${2:?公证 p8 的实际文件路径}"
[[ -t 0 ]] || { echo "请在本机交互终端运行" >&2; exit 2; }
read -rs -p "p12 导出密码：" pass
echo >&2
cert() { printf '%s\n' "$pass" | openssl pkcs12 -in "$p12" -clcerts -nokeys -passin stdin; }
cert | openssl x509 -checkend 0 -noout
subject=$(cert | openssl x509 -noout -subject)
[[ "$subject" == *"Developer ID Application:"* ]] || { echo "需要 Developer ID Application 证书" >&2; exit 1; }
certkey=$(cert | openssl x509 -pubkey -noout)
privkey=$(printf '%s\n' "$pass" | openssl pkcs12 -in "$p12" -nocerts -nodes -passin stdin | openssl pkey -pubout)
[[ "$certkey" == "$privkey" ]] || { echo "p12 中证书与签名私钥不匹配" >&2; exit 1; }
openssl pkey -in "$p8" -noout -check >/dev/null
echo "通过：Developer ID Application 证书有效，含配对私钥，公证私钥可解析。"
