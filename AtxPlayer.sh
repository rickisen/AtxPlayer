#  |                         Atxplayer 2.0                                        |
#  |  A script that takes a foldername as input and attempts to play any          |
#  |  "adtox-files" in this folder in sync by launching two seperate VLC windows  |
#  |  Thereby not doing any encoding or muxing of the final files                 |
#  |  Also analyses the audio according to r128 standard.                         |
#  |  Depends on VLC, cocoaDialog, r128x and "Adtox Encoder Libs"                 |

#initial Variables
syncOffset="0.3" # time to wait between launching audio and video, may need to change depending on disk speed
LufsHigh="170"
LufsLow="220"
# --- apps to use
Dialog="/path/to/CocoaDialog.app/Contents/MacOS/CocoaDialog"
r128x="/path/AtxPlayer/r128x-cli"
ffmpeg="/path/to/ffmpeg" # version 1.2.1 supports chanellmapping, so mono detection works

# to get a cleaner path
InputDir="$1"
cd "$InputDir"
CurrentDir="$(pwd)"

# set up the header in the temporary analysis results-file
if [ ! -a .EbuValues.txt ]
then
        echo "FILE                                                         | LUFS   |   LU     |     dBTP "                                                     > .EbuValues.txt
fi

# main loop
for file in *.wav
do
        if (echo "$file" | grep ".*[A-Z][0-Z][A-Z][A-Z][A-Z][A-Z][0-9][0-9][0-9][0-9].*") # check if there are any adtox codes in this file's name.
        then
                # extract some variables from from the filename
                nakedCode="$(echo "$file"       | sed 's/.*\([A-Z][0-9][A-Z][A-Z][A-Z][A-Z][0-9][0-9][0-9][0-9]\).*/\1/' )"
                duration="$(echo "$nakedCode"   | sed 's/.*\([A-Z][A-Z][0-9][0-9]\).*/\1/' | sed 's/.*\([0-9][0-9]\).*/\1/' )"
                videoFile="$(echo "$file"       | sed 's?.wav?.m2v?')"

                # play the audio
                open -a VLC "$CurrentDir"/"$file"

                # wait so that the "Audio VLC" and the "Video VLC" sync up correctly
                sleep "$syncOffset"

                # play the video
                open -a VLC -n "$CurrentDir"/"$videoFile" # -n to spawn a new process even though VLC is already running

                # extract the active part of the audio for analysis, the ffmpeg command might need updating!!!
                "$ffmpeg" -ss 10 -t "$duration" -i "$file" .temp.wav > /dev/null
                "$ffmpeg" -i .temp.wav -map_channel 0.0.0 .temp--left.wav -map_channel 0.0.1 .temp-right.wav > /dev/null # two "--" on the left fix a bug

                #Analyze the audio (and clean up the garbled output from r128x-cli)
                "$r128x" .temp.wav |            grep "wav" | sed -e s?"\["?""?g -e s?"F"?""? -e s?"J"?""? -e s?"\^\[\^\["?""? -e s?".temp.wav"?"$nakedCode"?    >> .EbuValues.txt
                "$r128x" .temp--left.wav |      grep "wav" | sed -e s?"\["?""?g -e s?"F"?""? -e s?"J"?""? -e s?"\^\[\^\["?""? -e s?".temp--left.wav"?""?        > .left.txt
                "$r128x" .temp-right.wav |      grep "wav" | sed -e s?"\["?""?g -e s?"F"?""? -e s?"J"?""? -e s?"\^\[\^\["?""? -e s?".temp-right.wav"?""?        > .right.txt

                # Do mono/stereo analysis on the audio results
                left=$(md5 -q .left.txt)
                right=$(md5 -q .right.txt)
                if [ "$left" = "$right" ]
                then
                        echo "Warning, this file looks like it might be mono!"                                                                                  >> .EbuValues.txt
                fi

                # Do Loudness  analysis on the audio results
                Lufs=$(cat .EbuValues.txt | grep "$nakedCode" | awk '{print $2}' | sed -e s?"-"?""?g -e s?"\."?""?) # find the lufs value in the results
                if [[ "$Lufs" -lt "$LufsHigh" ]] # converted to positive insted of neagative. so it might look inverted
                then
                        echo "Loudness seams too High!"                                                                                                         >> .EbuValues.txt
                elif [[ "$Lufs" -ge "$LufsLow" ]]
                then
                        echo "Loudness seams too Low!"                                                                                                          >> .EbuValues.txt
                fi

                # new line for formatting reasons
                echo ""                                                                                                                                         >> .EbuValues.txt

                #Launch the "GUI" Dialog and save the button pressed in the button variable
                button=$("$Dialog" textbox --title "Adtox Player - "$nakedCode"" --text-from-file .EbuValues.txt --button1 "Next/Rename" --button2 "Next" --button3 "Quit all" --float)
                if [ "$button" == "3" ] # "quit all"
                then
                        killall VLC
                        rm .temp.wav .temp--left.wav .temp-right.wav
                        break
                elif [ "$button" == "1" ]  # rename the files
                then
                        mv -n "$file" "$nakedCode".wav
                        mv -n "$videoFile" "$nakedCode".m2v
                fi

                # reset so that we can go to the next file and restart everything
                killall VLC
                rm .temp.wav .temp--left.wav .temp-right.wav
        fi
done

# cleanup
if [ -a .EbuValues.txt ]
then
        rm .EbuValues.txt
        rm .left.txt
        rm .right.txt
fi

if [ -a .temp.wav ]
then
        rm .temp.wav
