#!/usr/bin/env bash
# Uploads an APK/AAB to AppGallery Connect via the AGC Publishing API and
# (optionally) submits it for review.
#
# Required env vars:
#   HUAWEI_CLIENT_ID      Connect API client id (team_client_id)
#   HUAWEI_CLIENT_SECRET  Connect API client secret
#   HUAWEI_APP_ID         AppGallery app id
#
# Usage: bash scripts/huawei_publish.sh <file.apk|file.aab> [submit]
#   submit: "true" (default) submits for review after upload; "false" leaves a draft.

set -euo pipefail

FILE_PATH="${1:?Usage: huawei_publish.sh <file> [submit]}"
SUBMIT_FOR_REVIEW="${2:-true}"
API="https://connect-api.cloud.huawei.com/api"

for var in HUAWEI_CLIENT_ID HUAWEI_CLIENT_SECRET HUAWEI_APP_ID; do
  if [ -z "${!var:-}" ]; then
    echo "Missing required env var: $var"
    exit 1
  fi
done

if [ ! -f "$FILE_PATH" ]; then
  echo "File not found: $FILE_PATH"
  exit 1
fi

FILE_EXT=$(echo "${FILE_PATH##*.}" | tr '[:upper:]' '[:lower:]')
FILE_NAME=$(basename "$FILE_PATH")
FILE_TYPE=5
[ "$FILE_EXT" = "apk" ] && FILE_TYPE=1

check_ret() {
  local body="$1" what="$2"
  local code
  code=$(printf '%s' "$body" | jq -r '.ret.code // empty' 2>/dev/null || true)
  if [ -n "$code" ] && [ "$code" != "0" ]; then
    echo "AGC API error ($what): $body"
    exit 1
  fi
}

echo "==> Obtaining access token"
TOKEN_RESP=$(curl -sS -X POST "$API/oauth2/v1/token" \
  -H 'Content-Type: application/json' \
  -d "{\"grant_type\":\"client_credentials\",\"client_id\":\"$HUAWEI_CLIENT_ID\",\"client_secret\":\"$HUAWEI_CLIENT_SECRET\"}")
ACCESS_TOKEN=$(printf '%s' "$TOKEN_RESP" | jq -r '.access_token // empty')
if [ -z "$ACCESS_TOKEN" ]; then
  echo "Failed to obtain access token: $TOKEN_RESP"
  exit 1
fi

AUTH=(-H "Authorization: Bearer $ACCESS_TOKEN" -H "client_id: $HUAWEI_CLIENT_ID")

echo "==> Getting upload URL (suffix=$FILE_EXT)"
UPLOAD_URL_RESP=$(curl -sS -X GET \
  "$API/publish/v2/upload-url?appId=$HUAWEI_APP_ID&suffix=$FILE_EXT&releaseType=1" \
  "${AUTH[@]}")
check_ret "$UPLOAD_URL_RESP" "upload-url"
UPLOAD_URL=$(printf '%s' "$UPLOAD_URL_RESP" | jq -r '.uploadUrl')
AUTH_CODE=$(printf '%s' "$UPLOAD_URL_RESP" | jq -r '.authCode')

echo "==> Uploading $FILE_NAME"
UPLOAD_RESP=$(curl -sS -X POST "$UPLOAD_URL" \
  -H 'Accept: application/json' \
  -F "authCode=$AUTH_CODE" \
  -F "fileCount=1" \
  -F "parseType=1" \
  -F "file=@$FILE_PATH")
if [ "$(printf '%s' "$UPLOAD_RESP" | jq -r '.result.UploadFileRsp.ifSuccess // 0')" != "1" ]; then
  echo "File upload failed: $UPLOAD_RESP"
  exit 1
fi
FILE_DEST_URL=$(printf '%s' "$UPLOAD_RESP" | jq -r '.result.UploadFileRsp.fileInfoList[0].fileDestUlr')
FILE_SIZE=$(printf '%s' "$UPLOAD_RESP" | jq -r '.result.UploadFileRsp.fileInfoList[0].size')

echo "==> Updating app file info (fileType=$FILE_TYPE)"
FILE_INFO_RESP=$(curl -sS -X PUT "$API/publish/v2/app-file-info?appId=$HUAWEI_APP_ID" \
  "${AUTH[@]}" -H 'Content-Type: application/json' \
  -d "{\"fileType\":\"$FILE_TYPE\",\"files\":[{\"fileName\":\"$FILE_NAME\",\"fileDestUrl\":\"$FILE_DEST_URL\",\"size\":\"$FILE_SIZE\"}]}")
check_ret "$FILE_INFO_RESP" "app-file-info"
PKG_VERSION=$(printf '%s' "$FILE_INFO_RESP" | jq -r '.pkgVersion[0] // empty')

echo "==> Package uploaded (pkgVersion=$PKG_VERSION)"

if [ "$SUBMIT_FOR_REVIEW" != "true" ]; then
  echo "Draft upload complete (submit skipped)."
  exit 0
fi

submit() {
  curl -sS -X POST "$API/publish/v2/app-submit?appid=$HUAWEI_APP_ID&releaseType=1" \
    "${AUTH[@]}" -H 'Content-Type: application/json'
}

echo "==> Submitting for review"
SUBMIT_RESP=$(submit)
RET_CODE=$(printf '%s' "$SUBMIT_RESP" | jq -r '.ret.code // empty')

# 204144727 = AAB still compiling on Huawei side -> poll compile status, then retry
if [ "$RET_CODE" = "204144727" ] && [ -n "$PKG_VERSION" ]; then
  echo "==> AAB compile in progress, polling status"
  for i in $(seq 1 30); do
    sleep 20
    STATUS_RESP=$(curl -sS -X GET \
      "$API/publish/v2/aab/complile/status?appId=$HUAWEI_APP_ID&pkgVersion=$PKG_VERSION" \
      "${AUTH[@]}")
    COMPILE_STATUS=$(printf '%s' "$STATUS_RESP" | jq -r '.aabCompileStatus // empty')
    echo "    aabCompileStatus=$COMPILE_STATUS ($i/30)"
    [ "$COMPILE_STATUS" = "2" ] && break
  done
  SUBMIT_RESP=$(submit)
  RET_CODE=$(printf '%s' "$SUBMIT_RESP" | jq -r '.ret.code // empty')
fi

if [ "$RET_CODE" = "0" ]; then
  echo "==> App submitted for review successfully"
else
  echo "Submit failed: $SUBMIT_RESP"
  exit 1
fi
