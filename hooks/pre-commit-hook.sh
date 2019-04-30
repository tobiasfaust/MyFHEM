#!/usr/bin/env bash

cd ~/IdeaProjects/MyFHEM/
controls_file="controls_echodevice.txt"

test -e "${controls_file}" && rm "${controls_file}"

while IFS= read -r -d '' FILE
do
    TIME=$(git log --pretty=format:%cd -n 1 --date=iso -- "$FILE")
    TIME=$(TZ=Europe/Berlin date -d "$TIME" +%Y-%m-%d_%H:%M:%S)
    FILESIZE=$(stat -c%s "$FILE")
	FILE=$(echo "$FILE"  | cut -c 3-)
	printf "UPD %s %-7d %s\n" "$TIME" "$FILESIZE" "$FILE"  >> controls.txt
done <   <(find ./FHEM -maxdepth 2 \( -name "*.pm" -o -name "*.txt" \) -print0 | sort -z -g)

git add $controls_file