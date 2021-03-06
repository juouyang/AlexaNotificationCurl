############################################################
# First we creat a bunch of variables to hold data.
############################################################
QUESTION=${1}

# Auth token (replace with yours).
TOKEN=`cat token.dat`

# Boundary name, must be unique so it does not conflict with any data.
BOUNDARY="BOUNDARY1234"
BOUNDARY_DASHES="--"

# Newline characters.
NEWLINE='\r\n';

# Metadata headers.
METADATA_CONTENT_DISPOSITION="Content-Disposition: form-data; name=\"metadata\"";
METADATA_CONTENT_TYPE="Content-Type: application/json; charset=UTF-8";

# Metadata JSON body.
METADATA="{\
\"messageHeader\": {},\
\"messageBody\": {\
\"profile\": \"alexa-close-talk\",\
\"locale\": \"en-us\",\
\"format\": \"audio/L16; rate=16000; channels=1\"\
}\
}"

echo ${METADATA} | python -m json.tool
# Audio headers.
AUDIO_CONTENT_TYPE="Content-Type: audio/L16; rate=16000; channels=1";
AUDIO_CONTENT_DISPOSITION="Content-Disposition: form-data; name=\"audio\"";

############################################################
# Then we start composing the body using the variables.
############################################################

# Compose the start of the request body, which contains the metadata headers and
# metadata JSON body as the first part of the multipart body.
# Then it starts of the second part with the audio headers. The binary audio
# will come later as you will see.
POST_DATA_START="
${BOUNDARY_DASHES}${BOUNDARY}${NEWLINE}${METADATA_CONTENT_DISPOSITION}${NEWLINE}\
${METADATA_CONTENT_TYPE}\
${NEWLINE}${NEWLINE}${METADATA}${NEWLINE}${NEWLINE}${BOUNDARY_DASHES}${BOUNDARY}${NEWLINE}\
${AUDIO_CONTENT_DISPOSITION}${NEWLINE}${AUDIO_CONTENT_TYPE}${NEWLINE}"

# Compose the end of the request body, basically just adding the end boundary.
POST_DATA_END="${NEWLINE}${NEWLINE}${BOUNDARY_DASHES}${BOUNDARY}${BOUNDARY_DASHES}${NEWLINE}"

############################################################
# Now we create a request body file to hold everything including the binary audio data.
############################################################

# Write metadata to a file which will contain the multipart request body content.
echo -e $POST_DATA_START > multipart_body.txt

# Here we append the binary audio data to request body file
# by spitting out the contents. We do it this way so that
# the encoding do not get messed with.
#cat $AUDIO_FILENAME >> multipart_body.txt
echo "Question: ${QUESTION}"
echo "Creating voice..."

espeak -v en-us "${QUESTION}" --stdout | tee espeak.out | sox - -c 1 -r 16000 -e signed -b 16 -t wav - >> multipart_body.txt
hexdump -C espeak.out -n 64
play espeak.out
rm -rf espeak.out

#rm -rf /tmp/pipe.wav;ln -s /dev/stdout /tmp/pipe.wav
#pico2wave -w /tmp/pipe.wav "${QUESTION}" | tee pico2wav.wav | sox - -c 1 -r 16000 -e signed -b 16 -t wav - >> multipart_body.txt
#hexdump -C pico2wav.wav -n 64
#play pico2wav.wav -q
#rm -rf pico2wav.wav

# Then we append closing boundary to request body file.
echo -e $POST_DATA_END >> multipart_body.txt

############################################################
# Finally we get to compose the cURL request command
# passing it the generated request body file as the multipart body.
############################################################

# Compose cURL command and write to output file.
echo "Making request..."
curl -i -s -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: multipart/form-data; boundary=${BOUNDARY}" \
  --data-binary @multipart_body.txt \
  https://access-alexa-na.amazon.com/v1/avs/speechrecognizer/recognize > response.txt
echo "Recieving response..."
http-message-parser ./response.txt --pick=multipart[0].body > message.json
python -m json.tool message.json

http-message-parser ./response.txt --pick=multipart[1].body > response1.mp3
FILE_TYPE=`file -b response1.mp3`
if [[ $FILE_TYPE == data ]]; then
	hexdump -C response1.mp3 -n 64
	play response1.mp3
fi
http-message-parser ./response.txt --pick=multipart[2].body > response2.mp3
FILE_TYPE=`file -b response2.mp3`
if [[ $FILE_TYPE == data ]]; then
	hexdump -C response2.mp3 -n 64
	play response2.mp3
fi

ART_URL=`cat message.json | jq --raw-output '.messageBody.directives[] | select(.namespace| startswith("TemplateRuntime")) | .payload.content.art.sources | select(.!=null) | .[] | select(.size| startswith("x-large")) | .url'`
if [[ ! -z "$ART_URL"  && $ART_URL == http* ]]; then
	echo "feh "$ART_URL
	feh "$ART_URL"
fi
STREAM_URL=`cat message.json | jq --raw-output '.messageBody.directives[] | select(.name | startswith("play")) | .payload.audioItem.streams[].streamUrl | select(.| startswith("https"))'`
if [[ ! -z "$STREAM_URL"  && $STREAM_URL == http* ]]; then
	echo "cvlc "$STREAM_URL
	cvlc --quiet "$STREAM_URL" vlc://quit
fi