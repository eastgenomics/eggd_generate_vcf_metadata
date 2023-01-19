# eggd_generate_vcf_metadata

## What does this app do?

Generate a zip of 5 YAML config files (files, manifest, clinical, individual and sample; see below for examples) from a given VCF filename for importing into openCGA.

## What are typical use cases for this app?

Required for generating metadata to import VCFs into openCGA.

## What data are required for this app to run?

- one or more VCF files, will always use the first VCF name for generating metadata from.
- assay config JSON file (see below)
- validate_name (boolean) - controls if to validate sample name structure from vcf

### Assay config

The assay JSON config file allows for passing in data to any of the 5 metadata files generated by defining the appropriate keys and values, which are then converted into the YAML structure. This should contain 5 top level keys corresponding to each of the metadata files generated, inside of which extra metadata for that file may be defined.

Example section of JSON config file for clinical metadata:
```
{
    "clinical": {
        "disorder": {
            "id": "HaemOnc"
        },
        "panels": {
            "id": "haemonc_genes_all"
        },
        "priority": {
            "id": "HIGH"
        },
        "type": "CANCER",
        "id": "MYE-"
    },
    "individuals": {
      ...
```

This would then produce the following `clinical.yaml` file:
```
- disorder:
    id: HaemOnc
  id: MYE-22096Z0052
  panels:
  - id: haemonc_genes_all
  priority:
    id: HIGH
  proband:
    id: '22096Z0052'
    samples:
    - id: 2203243
  status:
    id: READY_FOR_INTERPRETATION
  type: CANCER
```

n.b. `proband - id` and `proband - samples - id` are parsed from the vcf name.

A populated example may be found at `example/example_metadata_config.json`, and a template with the minimum required fields is given at `example/template_config.json`.


## What does this app output?

This app outputs a zip of 5 YAML config files for openCGA upload process.

Example metadata files generated may be seen below generated from vcf name ``.
This assumes the following structure for a given vcf name:

*
*
*
*
*
*

n.b. validation of each of the fields is performed to ensure it matches the above structure and so that malformed metadata files are not generated. This may be skipped by specifying `-validate_name=false`.


**files**
```
- id: 'path/to/vcf'
  software:
    name: 'softwareName'
```

* `id` is a path to where the vcf is being uploaded in openCGA, if specified the vcf filename will be appeneded and written to the config. If not the path will default to `data/{YYYYMM}`.
* `software - name`: name of variant caller used to generate the VCF. If not specified this will attempt to be inferred from the vcf header.


**manifest.yaml**

```
configuration:
  projectId: 
study:
  id: 
```

* `configuration - projectId`: should be defined in assay config
* `study - id`: should be defined in assay config


**samples.yaml**

```
- id: 'vcf_name_field_1'
  individualId: 'vcf_name_field_2'
  somatic: true
```

* `somatic`: should be defined in assay config


**individuals.yaml**

```
disorders:
- id: 
id: 'vcf_name_field_2'
name: 'vcf_name_field_2'
sex:
  id: 'vcf_name_field_5
```
* `disorders - id`: should be defined in assay config


**clinical.yaml**

```
- disorder:
    id: 
  id: 
  panels:
  - id: 
  priority:
    id: 
  proband:
    id: 'vcf_name_field_2'
    samples:
    - id: 'vcf_name_field_1'
  status:
    id: READY_FOR_INTERPRETATION
  type: 
```
* `id`: should be defined in assay config; will be formatted as `{id}{vcf_name_field_2}`. This is the ID for creation of the case in IVA.
* `disorder - id`: should be defined in assay config
* `panels - id`: should be defined in assay config
* `priority - id`: should be defined in assay config
* `type`: should be defined in assay config
