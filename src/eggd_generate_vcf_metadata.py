import gzip
import json
from pprint import PrettyPrinter
import re
from typing import Union
from zipfile import ZipFile

import dxpy
import yaml

PPRINT = PrettyPrinter(indent=2).pprint


def read_templates() -> Union[dict, dict, dict, dict]:
    """
    Reads YAML config templates from resources/home/dnanexus/templates/

    Returns
    -------
    Union[dict, dict, dict, dict]
        dicts of read in YAML templates
    """
    with open('templates/clinical.yaml') as fh:
        clinical = yaml.safe_load(fh)
        print(f"clinical.yaml template: {clinical}")

    with open('templates/individuals.yaml') as fh:
        individuals = yaml.safe_load(fh)
        print(f"individuals.yaml template: {individuals}")

    with open('templates/manifest.yaml') as fh:
        manifest = yaml.safe_load(fh)
        print(f"manifest.yaml template: {manifest}")

    with open('templates/samples.yaml') as fh:
        samples = yaml.safe_load(fh)
        print(f"samples.manifest template: {samples}")

    return clinical, individuals, manifest, samples


def read_vcf_header(vcf) -> list:
    """
    Read in header lines from vcf to list

    Parameters
    ----------
    vcf : str
        name of vcf file to read from

    Returns
    -------
    list
        header lines parsed from vcf

    Raises
    ------
    RuntimeError
        Raised when non-vcf passed
    """
    print(f"Reading from file: {vcf}")

    if vcf.endswith('.vcf'):
        file_handle = open(vcf)
    elif vcf.endswith('.vcf.gz'):
        file_handle = gzip.open(vcf)
    else:
        # doesn't appear to be a vcf
        raise RuntimeError(
            f"Invalid file passed - not a vcf: {vcf}"
        )

    header = []
    while True:
        line = file_handle.readline()
        if line.startswith('#'):
            header.append(line)
        else:
            break

    file_handle.close()

    print(f"Size of header parsed from vcf: {len(header)}")

    return header


def parse_samplename(sample, validate_name) -> list:
    """
    Split samplename into constituent parts and validate format

    Parameters
    ----------
    sample : str
        samplename parsed from vcf filename
    validate_name : bool
        controls if to validate fields of sample name

    Returns
    -------
    name_fields : list
        list of field names parsed from samplename

    Raises
    ------
    AssertionError
        Raised when samplename does not have 6 fields
    RuntimeError
        Raised when one or more fields does not match expected format
    """
    name_fields = sample.split('-')

    if not validate_name:
        print("Skipping sample name validation")
        return name_fields

    # basic check we have correct number of fields
    assert len(name_fields) == 6, "Samplename has incorrect number of fields"

    # mapping of field to expected string format
    field_format = {
        1: r"",
        2: r"",
        3: r"",
        4: r"",
        5: r"",
        6: r""
    }

    # test fields are formatted as expected
    errors = []
    for idx, field in name_fields:
        if not re.search(field_format[idx + 1], field):
            errors.append(field)

    if errors:
        raise RuntimeError(
            f"Error(s) in sample name format: {', '.join(errors)}"
        )

    return name_fields


def infer_caller(vcf_header) -> str:
    """
    Try infer variant caller from vcf header

    Parameters
    ----------
    vcf_header : list
        header parsed from vcf

    Returns
    -------
    str
        identified variant caller
    """
    # mapping of string found in vcf header to name we want
    callers = {
        'pindel': 'cgpPindel',
        'tnhaplotyper2': 'TNhaplotyper2',
        'pisces': 'Pisces',
        'sentieoncommandline.haplotyper': 'GATK HaplotypeCaller'
    }

    for caller, name in callers.items():
        if any([caller in x.lower() for x in vcf_header]):
            print(f"Variant caller identified from vcf: {name}")
            return name

    print("Could not determine variant caller from header of vcf")
    return "unknown"


def write_manifest(config, template):
    """
    Populate and write the manifest.yaml file

    Parameters
    ----------
    config : dict
        json config for assay
    template : dict
        manifest.yaml config read in with yaml.safe_loads()

    Outputs
    -------
    manifest.yaml
    """
    # update template with any values from config
    if config.get('manifest'):
        template.update(config['manifest'])

    print("Populated manifest.yaml writing to file:")
    PPRINT(template)

    with open('manifest.yaml', 'w') as fh:
        yaml.dump(template, fh)


def write_individuals(config, template, individual_id, sex):
    """
    Populate and write the individuals.yaml file

    Parameters
    ----------
    config : dict
        json config for assay
    template : dict
        manifest.yaml config read in with yaml.safe_loads()
    individual_id : str
        indiviudal ID parsed from samplename
    sex : str
        sex parsed from samplename

    Outputs
    -------
    individuals.yaml
    """
    # update template with any values from config
    if config.get('individuals'):
        template.update(config['individuals'])

    # add in required fields
    template['id'] = individual_id
    template['name'] = individual_id
    template['sex']['id'] = sex

    print("Populated individuals.yaml writing to file:")
    PPRINT(template)

    with open('individuals.yaml', 'w') as fh:
        yaml.dump(template, fh)


def write_samples(config, template, individual_id, sample_id):
    """
    Populate and write the samples.yaml file

    Parameters
    ----------
    config : dict
        json config for assay
    template : dict
        manifest.yaml config read in with yaml.safe_loads()
    individual_id : str
        indiviudal ID parsed from samplename
    sample_id : str
        sample ID parsed from samplename

    Outputs
    -------
    samples.yaml
    """
    # update template with any values from config
    if config.get('samples'):
        template[0].update(config['samples'])

    # add in required fields
    template[0]['id'] = sample_id
    template[0]['individualId'] =  individual_id

    print(f"Populated samples.yaml writing to file: {template}")

    with open('samples.yaml', 'w') as fh:
        yaml.dump(template, fh)


def write_clinical(config, template, individual_id, sample_id):
    """
    Populate and write the clinical.yaml file

    Parameters
    ----------
    config : dict
        json config for assay
    template : dict
        clinical.yaml config read in with yaml.safe_loads()
    individual_id : str
        indiviudal ID parsed from samplename
    sample_id : str
        sample ID parsed from samplename

    Outputs
    -------
    clinical.yaml
    """
    # update template with any values from config
    if config.get('clinical'):
        template.update(config['clinical'])

    # add in required fields
    template['id'] = individual_id
    template['proband']['id'] = individual_id
    template['proband']['samples'][0]['id'] = sample_id

    print(f"Populated clinical.yaml writing to file: {template}")

    with open('clinical.yaml', 'w') as fh:
        yaml.dump(template, fh)


@dxpy.entry_point('main')
def main(vcfs, assay_config, validate_name):
    """
    Main entry point for app

    Parameters
    ----------
    vcfs : list
        input vcf(s) to use to generate metadata, will use first
        one if more than one passed
    assay_config : dict
        dnanexus_link to file ID of given assay config, contains assay
        specific values to add to each of the metadata YAML files
    validate_name : bool
        controls if to validate fields of sample name

    Returns
    -------
    dict
        dnanexus_link of uploaded config file zip file ID
    -------
    """
    # get samplename and download vcf
    file = dxpy.DXFile(vcfs[0]['$dnanexus_link'])
    file_name = file.describe()['name']
    file_prefix = file_name.replace('.vcf', '').replace('.gz', '')
    dxpy.download_dxfile(file, file_name)

    # split name and validate parts
    instrument_id, individual_id, clarity_id, epic_code, \
        sex, probeset = parse_samplename(file_name, validate_name)

    # try parse caller from vcf header
    header = read_vcf_header(file_name)
    caller = infer_caller(header)

    # read in given  assay config and yaml templates
    clinical, individuals, manifest, samples = read_templates()
    config = json.loads(dxpy.DXFile(assay_config['$dnanexus_link']).read())

    print("Config file values given to add to metadata configs:")
    PPRINT(config)

    # populate templates and write to file
    write_manifest(config, manifest)
    write_individuals(config, individuals, individual_id, sex)
    write_samples(config, samples, individual_id, instrument_id)
    write_clinical(config, clinical, individual_id, instrument_id)

    # zip written files and add as output
    outname = f"{file_prefix}.opencga_configs.zip"
    with ZipFile(outname, 'w') as fh:
        fh.write('manifest.yaml')
        fh.write('individuals.yaml')
        fh.write('samples.yaml')
        fh.write('clinical.yaml')

    outfile = dxpy.upload_local_file(outname)
    return {'config_zip': dxpy.dxlink(outfile)}

dxpy.run()
