#!/bin/bash
# eggd_generate_vcf_metadata

set -exo pipefail

_generate_clinical () {
    # generates clinical.yaml file
    mark-section "Generating clinical.yaml"

    local disorder=$1
    local opencga_sample_id=$2
    local panel=$3
    local priority=$4
    local individual_id=$5
    local sample_id=$6
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
        "'${individual_id}'" "${sample_id}" "${status}" "${type}"\
        | sed "s/^[ ]\{4\}//g; /^$/d" > clinical.yaml
}

_generate_individuals () {
    # generates individuals.yaml
    mark-section "Generating individuals.yaml"

    local disorder=$1
    local individual_id=$2
    local sex=$3

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
    ''' "$disorder" "'$individual_id'" "'$individual_id'" "$sex" \
    | sed "s/^[ ]\{4\}//g; /^$/d" > individuals.yaml
}

_generate_manifest () {
    # generates manifest.yaml file
    mark-section "Generating manifest.yaml"

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
    mark-section "Generating samples.yaml"

    local sample_id=$1
    local individual_id=$2
    local somatic=$3

    printf '''
    - id: %s
      individualId: %s
      somatic: %s
    ''' "$sample_id" "'$individual_id'" "$somatic" \
    | sed "s/^[ ]\{4\}//g; /^$/d" > samples.yaml
}

_validate_myeloid_name () {
  # function to check if given myeloid sample names are valid
  # $1 -> full vcf name string
  mark-section "Validating sample name"
  local vcf_name=$1

  if [[ "${vcf_name,,}" == *"oncospan"* ]] || [[ "$vcf_name,," == *"TMv2OCT20"* ]]
  then
    # sample is a control => skip as we won't upload
    echo "Sample is a control: ${vcf_name}"
    echo "Exiting now as controls won't be uploaded."
    dx tag "$DX_JOB_ID" "Control sample: no metadata generated"
    exit 0
  fi

  # split out name to array to check
  IFS='-' read -a arr <<< "$vcf_name"

  # sampleID-individualID-seqAttempt-sampleType-assay-MYE-sex-EGG2
  # e.g. 2200626-22006Z0026-2-PB-MPD-MYE-F-EGG2
  if ! expr "${arr[0]}" : "^[0-9]*$" >/dev/null || \
      ! expr "${arr[1]}" : "^[0-9A-Za-z]*$" >/dev/null || \
      ! expr "${arr[2]}" : "^[0-9]$" >/dev/null || \
      ! expr "${arr[-3]}" : "MYE" >/dev/null || \
      ! expr "${arr[-2]}" : "[MFUN]" >/dev/null || \
      ! expr "${arr[-1]}" : "EGG2" >/dev/null
  then
    # some part of sample name invalid
    printf "\nSample name appears to be invalid: %s\n" "$vcf_name"
    printf "\nExiting now.\n"
    exit 1
  else
    printf "\nValid sample name: %s\n" "$vcf_name"
  fi
}


_myeloid_configs () {
    # generates config files for myeloid samples
    local vcf_name=$1

    # split vcf filename parts to an array
    # first 8 fields of sample name separate + rest (e.g. _S11_L001...)
    # 8 fields should look like:
    #   sampleID-individualID-seqAttempt-sampleType-assay-MYE-sex-EGG2
    #   1234Z5678-123456-1-BM-MPD-MYE-F-EGG2
    IFS='-' read -a arr <<< "$vcf_name"

    # sense check parsed out sample names parts are correct
    # unless validate_name is set to false
    if [ "$validate_name" = true ]; then
      _validate_myeloid_name "$vcf_name"
    fi

    # generate clinical.yaml -> pass zetta case ID (from individual ID (1)),
    # individualID (1) and sampleID (0)
    _generate_clinical "HaemOnc" "H${arr[1]}M" "haemonc_genes_all" \
                        "HIGH" "${arr[1]}" "${arr[0]}" \
                        "READY_FOR_INTERPRETATION" "CANCER"

    # generate individuals.yaml -> pass individual ID & sex
    _generate_individuals "HaemOnc" "${arr[1]}" "${arr[-2]}"

    # generate manifest.yaml
    _generate_manifest "cancer_grch38" "myeloid"

    # generate samples.yaml -> pass sampleID (1) and individualID (2)
    _generate_samples "${arr[0]}" "${arr[1]}" "true"
}

main() {
    # input is array, select the first to get name from
    # awk to get out the file ID as it is formatted as
    # {"$dnanexus_link": "file-xxx"}
    local vcf
    local vcf_name
    local full_name

    vcf=$(awk -F'"' '{print $4}' <<< "${vcfs[0]}")
    vcf_name=$(dx describe --json "${vcf}" | jq -r '.name')

    echo "Using vcf ID: '$vcf'"
    echo "Using vcf name: $vcf_name"

    # get just the full sample name (i.e. sample name + _S[0-9]{1,2}_L001)
    # used to name output zip file
    full_name=$(cut -d'_' -f-3 <<< "$vcf_name")

    # generate required yaml files
    if [[ "$vcf_name" =~ "EGG2" ]]; then
        # check VCF is haemonc
       _myeloid_configs "$vcf_name"
    else
        # exit since this only handles myeloid samples for now
        printf "%s does not appear to be a haemonc VCF file. Exiting now" "$vcf_name"
        exit 1
    fi

    # check all files have been written
    if [ ! -f samples.yaml ] || [ ! -f clinical.yaml ] || \
       [ ! -f individuals.yaml ] || [ ! -f manifest.yaml ];
       then
          printf "One or more config files not generated"
          printf "Configs written: %s" "$(find . -name '*.yaml')"
          printf "Exiting now."
          exit 1
    fi

    # cat files to be in logs for easier checking if needed
    for file in ./*.yaml; do cat "$file"; done

    # zip yaml files for upload
    zip --junk-paths "${full_name}.opencga_configs.zip" \
        clinical.yaml individuals.yaml manifest.yaml samples.yaml

    # upload zip of configs
    mark-section "Uploading output file"
    zip=$(dx upload "${full_name}.opencga_configs.zip" --brief)
    dx-jobutil-add-output config_zip "$zip" --class=file
}
