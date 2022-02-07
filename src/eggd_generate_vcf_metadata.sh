#!/bin/bash
# eggd_generate_vcf_metadata

set -exo pipefail

_generate_clinical () {
    # generates clinical.yaml file
    local disorder=$1
    local opencga_sample_id=$2
    local panel=$3
    local priority=$4
    local individual_id=$5
    local sample_name=$6
    local status=$7
    local type=$8

    printf '''
    - disorder:
        id: %s
      id: %s
      panels:
      - id: %s
      priority:
        id: %s
      proband:
        id: %s
        samples:
        - id: %s
      status:
        id: %s
      type: %s
    ''' "${disorder}" "${opencga_sample_id}" "${panel}" "${priority}" \
        "'${individual_id}'" "${sample_name}" "${status}" "${type}"\
        | sed "s/^[ ]\{4\}//g; /^$/d" > clinical.yaml
}

_generate_individuals () {
    # generates individuals.yaml
    local disorder=$1
    local id=$2
    local name=$3
    local sex=$4

    # map single char sex values to words
    if [[ "$sex" == "F" ]]; then
        sex="Female"
    elif [[ "$sex" == "M" ]]; then
        sex="Male"
    else
        sex="Unknown"
    fi

    printf '''
    disorders:
    - id: %s
    id: %s
    name: %s
    sex:
      id: %s
    ''' "$disorder" "'$id'" "'$name'" "$sex" \
    | sed "s/^[ ]\{4\}//g; /^$/d" > individuals.yaml

}

_generate_manifest () {
    # generates manifest.yaml file
    local project=$1
    local study=$2

    printf '''
    configuration:
      projectId: %s
    study:
      id: %s
    ''' "$project" "$study" \
    | sed "s/^[ ]\{4\}//g; /^$/d" > manifest.yaml

}

_generate_samples () {
    # generates samples.yaml
    local sample_name=$1
    local individual_id=$2
    local somatic=$3

    printf '''
    - id: %s
      individualId: %s
      somatic: %s
    ''' "$sample_name" "'$individual_id'" "$somatic" \
    | sed "s/^[ ]\{4\}//g; /^$/d" > samples.yaml
}

_myeloid_configs () {
    # generates config files for myeloid samples

    # split vcf filename parts to an array
    # first 7 fields of sample name separate + rest (e.g. _S11_L001...)
    IFS='-' read -a arr <<< "$vcf_name"

    _generate_clinical "HaemOnc" "H${arr[1]}" "haemonc_genes_all" \
                        "HIGH" "${arr[0]}" "${arr[1]}" \
                        "READY_FOR_INTERPRETATION" "CANCER"

    _generate_individuals "HaemOnc" "${arr[0]}" "${arr[0]}" "${arr[5]}"

    _generate_manifest "cancer_grch38" "myeloid"
    _generate_samples "${arr[1]}" "${arr[0]}" "true"

}

main() {

    # input is array, select the first to get name from
    # awk to get out the file ID as it is formatted as
    # {"$dnanexus_link": "file-xxx"}
    vcf=$(awk -F'"' '{print $4}' <<< "${vcf[0]}")
    vcf_name=$(dx describe --json "${vcf}" | jq -r '.name')

    echo "vcf ID: '$vcf'"
    echo "vcf name: $vcf_name"

    # _prefix won't work, get prefix ourselves
    IFS='.' read -r vcf_prefix _ <<< "$vcf_name"

    # get just the sample name (i.e. sample name + _S[0-9]{1,2}_L001)
    sample_name=$(cut -d'_' -f-3 <<< "$vcf_name")

    # generate required yaml files
    if [[ "$vcf_name" =~ "EGG2" ]]; then
        # check VCF is haemonc
       _myeloid_configs "$sample_name"
    else
        # exit since this only handles myeloid samples for now
        printf "%s does not appear to be a haemonc VCF file. Exiting now" "$vcf_name"
        exit 1
    fi

    # cat files to be in logs for easier checking if needed
    for file in ./*.yaml; do cat "$file"; done

    # zip yaml files for upload
    zip --junk-paths "${sample_name}.opencga_configs.zip" \
        clinical.yaml individuals.yaml manifest.yaml samples.yaml

    # upload zip of configs
    zip=$(dx upload "${sample_name}.opencga_configs.zip" --brief)
    dx-jobutil-add-output config_zip "$zip" --class=file
}

