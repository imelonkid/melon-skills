# 示例：构建上下文要带上兄弟仓库（由流水线 melon-ci server-release 在构建前 source；见模板 deploy.sh 头部说明）。
# 上下文结构与本机开发时的相对位置一致：<ctx>/__NAME__（本仓库 tag 内容）+ <ctx>/__DEP__（兄弟仓库）。
# 兄弟仓库版本固定在 deploy/__DEP__.ref（它的 tag），升级 = 改这个文件并提交，再发服务端新版。
REF="$(tr -d '[:space:]' < "$SRC/deploy/__DEP__.ref")"
CTX="$(mktemp -d)"
mv "$SRC" "$CTX/__NAME__"; SRC="$CTX/__NAME__"
echo "▸ 依赖 __DEP__@$REF"
git clone -q --depth 1 --branch "$REF" https://github.com/imelonkid/__DEP__.git "$CTX/__DEP__"
rm -rf "$CTX/__DEP__/.git"
DOCKERFILE="$CTX/__NAME__/deploy/Dockerfile"
[[ -f "$CTX/__NAME__/deploy/Dockerfile.dockerignore" ]] && cp "$CTX/__NAME__/deploy/Dockerfile.dockerignore" "$CTX/.dockerignore"
trap 'rm -rf "$CTX"' EXIT
