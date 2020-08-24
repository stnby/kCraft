#!/bin/sh
# Copyright (c) 2020 Stnby <stnby@kernal.eu>
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

auth_player_name='Stnby'
game_directory=~/.minecraft

launcher_name='java-minecraft-launcher' # Ha except it's POSIX Shell...
launcher_version='1.6.84-j'

auth_uuid='00000000-0000-0000-0000-000000000000'
auth_access_token='null'
user_type='legacy'

assets_root="${game_directory}/assets"
libraries_root="${game_directory}/libraries"
versions_root="${game_directory}/versions"

case "$1" in
    get-manifest) # Downloads info about all client versions.
        curl --create-dirs -#o "${game_directory}/version_manifest.json" 'https://launchermeta.mojang.com/mc/game/version_manifest.json'
        ;;
    get-metadata) # Downloads metadata for selected client version.
        jq -j '.versions[] | "<b>", .id, "</b> ", .type, "\n"' "${game_directory}/version_manifest.json" \
            | rofi -dmenu -p 'version' -markup-rows -format 'i' \
            | xargs -I% \
                jq -M '.versions[%] | .id, .url' "${game_directory}/version_manifest.json" \
            | xargs sh -c \
                "echo \"Downloading: 'versions/\$0/\$0.json'\"; curl --create-dirs -C- -#o \"${versions_root}/\$0/\$0.json\" \$1"
        ;;
    get-client) # Downloads 'client.jar'.
        version_name="$2"
        [ ! -f "${versions_root}/${version_name}/${version_name}.json" ] && echo 'Such version does not exist' && exit 1
        echo "Downloading: 'versions/${version_name}/${version_name}.jar'"
        jq '.downloads.client.url' "${versions_root}/${version_name}/${version_name}.json" \
            | xargs curl -C- -#o "${versions_root}/${version_name}/${version_name}.jar"
        ;;
    get-assets) # Downloads game assets requiered for the client.
        version_name="$2"
        [ ! -f "${versions_root}/${version_name}/${version_name}.json" ] && echo 'Such version does not exist' && exit 1
        assets_index_name=`jq -r '.assetIndex.id' "${versions_root}/${version_name}/${version_name}.json"`
        jq -r '.assetIndex.url' "${versions_root}/${version_name}/${version_name}.json" \
            | xargs sh -c \
                "echo \"Downloading: 'assets/indexes/${assets_index_name}.json'\"; curl --create-dirs -C- -#o \"${assets_root}/indexes/${assets_index_name}.json\" \$0"
        jq '.objects[].hash' "${assets_root}/indexes/${assets_index_name}.json" \
            | xargs -n1 sh -c "printf 'https://resources.download.minecraft.net/%.2s/%s\n\tout=%.2s/%s\n' \$0 \$0 \$0 \$0" \
                    | aria2c -i- -x16 -c -d "${assets_root}/objects"
        ;;
    get-libs) # Downloads libraries requiered for the client.
        version_name="$2"
        [ ! -f "${versions_root}/${version_name}/${version_name}.json" ] && echo 'Such version does not exist' && exit 1
        jq '.libraries[].downloads[] | if has("natives-linux") then ."natives-linux" else if has("url") then . else empty end end | .path, .url' \
            "${versions_root}/${version_name}/${version_name}.json" \
                | xargs -n2 sh -c "printf '%s\n\tout=%s\n' \$1 \$0" \
                    | aria2c -i- -x16 -c -d ${libraries_root}
        ;;
    extract-natives) # Extracts native libraries into correct location from previous step. 
        version_name="$2"
        [ ! -f "${versions_root}/${version_name}/${version_name}.json" ] && echo 'Such version does not exist' && exit 1
        jq -r '.libraries[].downloads.classifiers."natives-linux".path // empty' "${versions_root}/${version_name}/${version_name}.json" \
            | xargs -n1 -I% unzip -n "${libraries_root}/%" -d "${versions_root}/${version_name}/natives"
        ;;
    start-client) # Starts the game. :)
        version_name="$2"
        [ ! -f "${versions_root}/${version_name}/${version_name}.json" ] && echo 'Such version does not exist' && exit 1
        version_type=`jq -r '.type' "${versions_root}/${version_name}/${version_name}.json"`
        assets_index_name=`jq -r '.assetIndex.id' "${versions_root}/${version_name}/${version_name}.json"`
        natives_directory="${versions_root}/${version_name}/natives"
        classpath=`jq -r '.libraries[].downloads[].path // empty' "${versions_root}/${version_name}/${version_name}.json" | xargs -n1 -I% printf "${libraries_root}/%:"; echo "${versions_root}/${version_name}/${version_name}.jar"`
        main_class=`jq -r '.mainClass' "${versions_root}/${version_name}/${version_name}.json"`
        java \
            -Xmx2G -Xss1M \
            -Dfile.encoding=UTF-8 \
            -Djava.library.path=${natives_directory} \
            -Dminecraft.launcher.brand=${launcher_name} \
            -Dminecraft.launcher.version=${launcher_version} \
            -cp ${classpath} ${main_class} \
            --username ${auth_player_name} \
            --version ${version_name} \
            --gameDir ${game_directory} \
            --assetsDir ${assets_root} \
            --assetIndex ${assets_index_name} \
            --uuid ${auth_uuid} \
            --accessToken ${auth_access_token} \
            --userType ${user_type} \
            --versionType ${version_type}
        ;;
    *) echo 'Go ahead and read the source code.'
esac
