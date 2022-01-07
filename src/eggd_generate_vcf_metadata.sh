#!/bin/bash
# eggd_generate_vcf_metadata

set -exo pipefail

main() {

    echo "Value of vcf: '$vcf'"

    # split vcf filename parts to an array
    IFS='-' read -a arr <<< $vcf_name

    # create json from file name parts, formatted from haemonc file naming
    json="$vcf_prefix-metadata.json"

    printf '''{
        "Filename": "%s", "Individual ID":"%s", "Sample ID": "%s",
        "Sex": "%s", "Panel": "all haem onc", "Disorder": "HaemOnc", "CaseID": "%s"
    }''' "${file}" "${arr[0]}" "${arr[1]}" "${arr[5]}" "H${arr[0]}_1" | jq '.' > "$json"


    json=$(dx upload "$json" --brief)
    dx-jobutil-add-output json "$json" --class=file
}
