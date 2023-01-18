# eggd_generate_vcf_metadata

## What does this app do?

Generate a zip of YAML config files from a given VCF filename for importing into openCGA.

## What are typical use cases for this app?

Required for generating metadata to import VCF into openCGA.

## What data are required for this app to run?

- one or more VCF files, will always use the first VCF name for generating metadata from.
- assay config JSON file (see below)
- validate_name (boolean) - controls if to validate sample name structure from vcf

### Assay config


## What does this app output?

This app outputs a zipn of YAML config files for openCGA upload process.

Example configs given below from sample name: `123456-1234Z5678-1-BM-MPD-MYE-F-EGG2`

**manifest.yaml**

```
configuration:
  projectId: cancer_grch38
study:
  id: myeloid

```


**samples.yaml**

```
- id: '123456'
  individualId: '1234Z5678'
  somatic: true

```



**individuals.yaml**

```
disorders:
- id: HaemOnc
id: '1234Z5678'
name: '1234Z5678'
sex:
  id: Female

```


**clinical.yaml**

```
- disorder:
    id: HaemOnc
  id: H1234Z5678M
  panels:
  - id: haemonc_genes_all
  priority:
    id: HIGH
  proband:
    id: '1234Z5678'
    samples:
    - id: 123456
  status:
    id: READY_FOR_INTERPRETATION
  type: CANCER

```
