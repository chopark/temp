cd /home/ubuntu/jarvis-nifi/conf
sed -i 's/nifi.remote.input.host=.*/nifi.remote.input.host=172.31.30.86/' nifi.properties
sed -i 's/nifi.web.http.host=.*/nifi.web.http.host=172.31.30.86/' nifi.properties
cd /home/ubuntu/jarvis-nifi/bin
rm -rf ../content_repository/* ../provenance_repository/* ../flowfile_repository/* ../state/local/* ../logs/*
sudo ./nifi.sh start
