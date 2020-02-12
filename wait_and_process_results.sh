#!/bin/bash
## USAGE
## ./wait_and_process_results.sh (sleep time)
#### e.g. (sleep time): 60s, 10m, 1h

SHELL=$0

if [ $# != 1 ]; then
    echo "$SHELL: USAGE: $SHELL (sleep time)"
    echo "$SHELL: e.g. (sleep time): 60s, 10m, 1h"
    exit 1
fi

# Directories
HOME="/home/ubuntu"
NIFI_HOME="$HOME/jarvis-nifi"
NIFI_LOG="$NIFI_HOME/logs"
NIFI_SCRIPT="$NIFI_HOME/scripts"
NIFI_BIN="$NIFI_HOME/bin"
NIFI_RESULTS="$NIFI_HOME/results"
MINIFI_DIR="$HOME/minifi"
MINIFI_HOME="$MINIFI_DIR/minifi-0.5.0"
MINIFI_BIN="$MINIFI_HOME/bin"
MINIFI_SCRIPT="$MINIFI_DIR/scripts"
sudo chown -R ubuntu:ubuntu $NIFI_HOME
# Start NiFi
sudo sh $HOME/restart_nifi.sh

# Get your current server ip.
IP=`ifconfig eth0 | grep 'inet ' | cut -d: -f2 | awk '{ print $2}'`
FINAL_QUEUE_ID="1cebae29-016f-1000-96fd-971ebcf4d231"
LOG_PROCESSOR_ID="d02bb153-016c-1000-3bed-7ffc10e019d1"

echo "$SHELL: Checking flowFilesQueued...";echo;
# Parse flowFilesQueued.
FLOWFILESQUEUED=`curl "http://$IP:8080/nifi-api/connections/$FINAL_QUEUE_ID" -X GET | cut -d: -f61 | cut -d, -f1`
echo "$SHELL: flowFilesQueued: $FLOWFILESQUEUED"; echo;

# If the final queue in our dataflow contains any pending flowfiles to be processed, clean it.
while [ -z "$FLOWFILESQUEUED" ]; do
    sleep 5s
    FLOWFILESQUEUED=`curl "http://$IP:8080/nifi-api/connections/$FINAL_QUEUE_ID" -X GET | cut -d: -f61 | cut -d, -f1`
    echo "$SHELL: flowFilesQueued: $FLOWFILESQUEUED"; echo;
done
echo "$SHELL: flowFilesQueued: $FLOWFILESQUEUED"; echo;

echo "$SHELL: NiFi ready, start MiNiFi."
# Restart MiNiFi
aws ssm send-command --targets "Key=tag:type,Values=edge" \
--document-name "AWS-RunShellScript" \
--comment "start MiNiFi" \
--parameters commands="sudo sh $HOME/scripts/restart_minifi.sh" \
--output text

echo "$SHELL: FlowFiles will be parsed with your NiFi IP($IP)"
echo "$SHELL: Sleeping $1..."
# Sleep as input time.
sleep $1

# Stop MiNiFi
aws ssm send-command --targets "Key=tag:type,Values=edge" \
--document-name "AWS-RunShellScript" \
--comment "stop MiNiFi" \
--parameters commands="sudo $MINIFI_BIN/minifi.sh stop" \
--output text

echo "$SHELL: Checking flowFilesQueued...";echo;
# Parse flowFilesQueued.
FLOWFILESQUEUED=`curl "http://$IP:8080/nifi-api/connections/$FINAL_QUEUE_ID" -X GET | cut -d: -f61 | cut -d, -f1`
echo "$SHELL: flowFilesQueued: $FLOWFILESQUEUED"; echo;

# If the final queue in our dataflow contains any pending flowfiles to be processed, clean it.
# After text '--data-binary', calling $LOG_PROCESSOR_ID did not work for some reason. So I put the ID value instead of $LOG_PROCESSOR_ID.
if [ ! -z "$FLOWFILESQUEUED" -a "$FLOWFILESQUEUED" != 0 ]; then
    echo "$SHELL: Cleaning up pending flowfiles..."

    curl "http://$IP:8080/nifi-api/processors/$LOG_PROCESSOR_ID" -X PUT -H 'Content-Type: application/json' -H 'Accept: application/json, text/javascript, */*; q=0.01' --data-binary '{"revision":{"clientId":"d02bb153-016c-1000-3bed-7ffc10e019d1","version":0},"component":{"id":"d02bb153-016c-1000-3bed-7ffc10e019d1","state":"RUNNING"}}';echo; echo;
    
    while [ $FLOWFILESQUEUED != 0 ] ; do
        sleep 2s
        FLOWFILESQUEUED=`curl "http://$IP:8080/nifi-api/connections/$FINAL_QUEUE_ID" -X GET | cut -d: -f61 | cut -d, -f1`
        echo "$SHELL: flowFilesQueued: $FLOWFILESQUEUED"; echo;
    done
    
    echo; curl "http://$IP:8080/nifi-api/processors/$LOG_PROCESSOR_ID" -X PUT -H 'Content-Type: application/json' -H 'Accept: application/json, text/javascript, */*; q=0.01' --data-binary '{"revision":{"clientId":"d02bb153-016c-1000-3bed-7ffc10e019d1","version":0},"component":{"id":"d02bb153-016c-1000-3bed-7ffc10e019d1","state":"STOPPED"}}';echo
fi  

FLOWFILESQUEUED=`curl "http://$IP:8080/nifi-api/connections/$FINAL_QUEUE_ID" -X GET | cut -d: -f61 | cut -d, -f1`
echo "$SHELL: flowFilesQueued: $FLOWFILESQUEUED"

# Stop NiFi
echo; read -p "$SHELL: Do you want to stop NiFi server? [y/n]" -n 1 -r
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo; echo "$SHELL: Stop running Nifi instance..."
    sudo sh $NIFI_BIN/nifi.sh stop
fi

sudo chown -R ubuntu:ubuntu $NIFI_HOME

# If there is old log_cat file, delete it.
if [ -f "$NIFI_LOG/log_cat" ]; then
    echo "$SHELL: Remove previous log_cat..."; echo;
   rm $NIFI_LOG/log_cat
fi

# Parse the log and show the result.
echo "$SHELL: Parsing the log..."
cat $NIFI_LOG/nifi-app* >> $NIFI_LOG/log_cat
python3 $NIFI_SCRIPT/extract_latencies.py $NIFI_LOG/log_cat > $NIFI_LOG/temp

echo; echo "RESULT"; echo "------------------------------------------"
tail -n 5 $NIFI_LOG/temp; echo "------------------------------------------"; echo

# Ask if you want to save it.
echo;read -p "$SHELL: Do you want to save this log? [y/n]" -n 1 -r
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo;echo "$SHELL: Done."
    exit 1
fi

# Save as
while true; do
    echo; read -p "$SHELL: Type a filename: " file_name
    if [ "$file_name" == "" ]; then
        echo "$SHELL: Please name it with non-empty string."
    elif [ -f "$NIFI_RESULTS/$file_name" ]; then
        echo "$SHELL: File exist. Please name it with other name."
    else
        break
    fi
done
cp $NIFI_LOG/temp $NIFI_RESULTS/$file_name
echo "$SHELL: Saving a file as $NIFI_RESULTS/$file_name"

echo;echo "$SHELL: Done."