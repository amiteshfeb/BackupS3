#Backup Script Start
dbname=$5
dbuser=$6
dbpassword=$7
filename=$8

echo 'Removing Old Files from Backup Folder..'
rm -rf backups/*
echo 'All Files removed from Backup Folder..'

echo 'Creating Database Backup Now...'
mysqldump -u$dbuser -p$dbpassword $dbname > backups/$dbname.sql 
echo 'Database Backup Created Successfully...'

echo 'Archiving Files & Folders from /public_html to /backups'
zip -r backups/$filename.zip public_html/
echo 'Archive Complete..'
#Backup Script End


#config var
path=$1 #/Users/nirajisotiya/Desktop/amzs3/foldertoupload
echo $path
bucket=hasbackups
region=eu-central-1
storageClass=STANDARD  # or 'REDUCED_REDUNDANCY' 'STANDARD'
awsAccess=$3
awsSecret=$4
subfolder=$2 #test/   # subfolder inside /hasbackups/test/  #don't include first / in folder path

m_openssl() {
  if [ -f /usr/local/opt/openssl@1.1/bin/openssl ]; then
    /usr/local/opt/openssl@1.1/bin/openssl "$@"
  elif [ -f /usr/local/opt/openssl/bin/openssl ]; then
    /usr/local/opt/openssl/bin/openssl "$@"
  else
    openssl "$@"
  fi
}

m_sed() {
  if which gsed > /dev/null 2>&1; then
    gsed "$@"
  else
    sed "$@"
  fi
}

awsStringSign4() {
  kSecret="AWS4$1"
  kDate=$(printf         '%s' "$2" | m_openssl dgst -sha256 -hex -mac HMAC -macopt "key:${kSecret}"     2>/dev/null | m_sed 's/^.* //')
  kRegion=$(printf       '%s' "$3" | m_openssl dgst -sha256 -hex -mac HMAC -macopt "hexkey:${kDate}"    2>/dev/null | m_sed 's/^.* //')
  kService=$(printf      '%s' "$4" | m_openssl dgst -sha256 -hex -mac HMAC -macopt "hexkey:${kRegion}"  2>/dev/null | m_sed 's/^.* //')
  kSigning=$(printf 'aws4_request' | m_openssl dgst -sha256 -hex -mac HMAC -macopt "hexkey:${kService}" 2>/dev/null | m_sed 's/^.* //')
  signedString=$(printf  '%s' "$5" | m_openssl dgst -sha256 -hex -mac HMAC -macopt "hexkey:${kSigning}" 2>/dev/null | m_sed 's/^.* //')
  printf '%s' "${signedString}"
}

upload() {
fileLocal="$1"
fileRemote="$subfolder${1##*/}"
echo "Uploading" "${fileLocal}" "->" "$fileRemote" "${bucket}" "${region}" "${storageClass}"

httpReq='PUT'
authType='AWS4-HMAC-SHA256'
service='s3'
baseUrl=".${service}.amazonaws.com"
dateValueS=$(date -u +'%Y%m%d')
dateValueL=$(date -u +'%Y%m%dT%H%M%SZ')
if hash file 2>/dev/null; then
  contentType="$(file -b --mime-type "${fileLocal}")"
else
  contentType='application/octet-stream'
fi

payloadHash=$(m_openssl dgst -sha256 -hex < "${fileLocal}" 2>/dev/null | m_sed 's/^.* //')
headerList='content-type;host;x-amz-content-sha256;x-amz-date;x-amz-server-side-encryption;x-amz-storage-class'
canonicalRequest="\
${httpReq}
/${fileRemote}

content-type:${contentType}
host:${bucket}${baseUrl}
x-amz-content-sha256:${payloadHash}
x-amz-date:${dateValueL}
x-amz-server-side-encryption:AES256
x-amz-storage-class:${storageClass}

${headerList}
${payloadHash}"

canonicalRequestHash=$(printf '%s' "${canonicalRequest}" | m_openssl dgst -sha256 -hex 2>/dev/null | m_sed 's/^.* //')

stringToSign="\
${authType}
${dateValueL}
${dateValueS}/${region}/${service}/aws4_request
${canonicalRequestHash}"

signature=$(awsStringSign4 "${awsSecret}" "${dateValueS}" "${region}" "${service}" "${stringToSign}")

curl -# -L --proto-redir =https -X "${httpReq}" -T "${fileLocal}" \
  --progress-bar \
  -H "Content-Type: ${contentType}" \
  -H "Host: ${bucket}${baseUrl}" \
  -H "X-Amz-Content-SHA256: ${payloadHash}" \
  -H "X-Amz-Date: ${dateValueL}" \
  -H "X-Amz-Server-Side-Encryption: AES256" \
  -H "X-Amz-Storage-Class: ${storageClass}" \
  -H "Authorization: ${authType} Credential=${awsAccess}/${dateValueS}/${region}/${service}/aws4_request, SignedHeaders=${headerList}, Signature=${signature}" \
  "https://${bucket}${baseUrl}/${fileRemote}" | tee /dev/null
}

for file in "$path"/*; do
  if [ -f "${file}" ]; then
      upload $file
   fi
done