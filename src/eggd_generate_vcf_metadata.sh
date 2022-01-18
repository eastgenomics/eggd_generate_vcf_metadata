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
        - id %s
      status:
        id: %s
      type: %s
    ''' "${disorder}" "${opencga_sample_id}" "${panel}" "${priority}" \
        "${individual_id}" "${sample_name}" "${status}" "${type}"\
        | sed "s/^[ ]\{4\}//g; /^$/d" > $HOME/clincal.yaml
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
    ''' "$disorder" "$id" "$name" "$sex" \
    | sed "s/^[ ]\{4\}//g; /^$/d" > $HOME/individuals.yaml

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
    | sed "s/^[ ]\{4\}//g; /^$/d" > $HOME/manifest.yaml

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
    ''' "$sample_name" "$individual_id" "$somatic" \
    | sed "s/^[ ]\{4\}//g; /^$/d" > $HOME/samples.yaml
}

_myeloid_configs () {
    # generates config files for myeloid samples
    
    # split vcf filename parts to an array
    IFS='-' read -a arr <<< "$vcf_name"

    # get just the sample name (i.e. first 10 fields)
    sample_name=$(cut -d'_' -f-3 <<< "$vcf_name")

    _generate_clinical "HaemOnc" "MYE-H${arr[0]}_1" "haemonc_genes_all" \
                        "HIGH" "${arr[0]}" "$sample_name" \
                        "READY_FOR_INTERPRETATION" "CANCER"

    _generate_individuals "HaemOnc" "${arr[0]}" "${arr[0]}" "${arr[5]}"

    _generate_manifest "cancer_grch38" "myeloid"

    _generate_samples "$sample_name" "${arr[0]}" "true"
}

main() {

    echo "Value of vcf: '$vcf'"
    echo "vcf name: $vcf_name"
    echo "vcf path: $vcf_path"

    # vcf_name="2108574-21274Z0040-PB-MPD-MYE-F-EGG2_S9_L001_markdup_recalibrated_tnhaplotyper2_allgenesvep.vcf"

    # _prefix won't work, get prefix ourselves
    IFS='.' read -r vcf_prefix _ <<< "$vcf_name"
    json="${vcf_prefix}.metadata.json"


    # generate required yaml files
    if [[ "$vcf_name" =~ "EGG2" ]]; then
        # check VCF is haemonc
       _myeloid_configs
    else
        # exit since this only handles myeloid samples for now
        printf "%s does not appear to be a haemonc VCF file. Exiting now" "$vcf_name"
        exit 1
    fi

    # zip yaml files for upload
    zip "${vcf_prefix}.opencga_configs.zip" \
        clincal.yaml individuals.yaml manifest.yaml samples.yaml

    # upload zip of configs
    json=$(dx upload "$config_zip" --brief)
    dx-jobutil-add-output json "$config_zip" --class=file
}

main
