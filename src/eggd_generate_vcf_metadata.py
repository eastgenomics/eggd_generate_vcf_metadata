import gzip
import json
import os
import pip
import re
from typing import Union
from zipfile import ZipFile

# Install required packages
for package in os.listdir("/home/dnanexus/packages"):
    print(f"Installing {package}")
    pip.main(["install", "--no-index", "--no-deps", f"packages/{package}"])

import dxpy
import yaml


def read_templates() -> Union[list, list, list, list]:
    """
    Reads yaml config templates from resources/home/dnanexus/templates/

    Returns
    -------
    Union[list, list, list, list]
        _description_
    """
    with open('templates/clinical.yaml') as fh:
        clinical = yaml.safe_load(fh)

    with open('templates/individuals.yaml') as fh:
        individuals = yaml.safe_load(fh)

    with open('templates/manifest.yaml') as fh:
        manifest = yaml.safe_load(fh)

    with open('templates/samples.yaml') as fh:
        samples = yaml.safe_load(fh)

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
    """
    print(f"Reading from file: {vcf}")
    if vcf.endswith('.vcf'):
        file_handle = open(vcf)
    if vcf.endswith('.vcf.gz'):
        file_handle = gzip.open(vcf)
    else:
        return None

    header = []
    while True:
        line = file_handle.readline()
        if line.startswith('#'):
            header.append(line)
        else:
            break

    file_handle.close()

    return header


def parse_samplename(sample) -> list:
    """
    Split samplename into constituent parts and validate format

    Parameters
    ----------
    sample : str
        samplename parsed from vcf filename

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

    with open('manifest.yaml') as fh:
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

    with open('individuals.yaml') as fh:
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
        template.update(config['samples'])

    # add in required fields
    template['id'] = sample_id
    template['individualId'] =  individual_id

    with open('samples.yaml') as fh:
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
    template['proband']['id'] = sample_id
    template['proband']['samples']['id']['individualId'] =  individual_id

    with open('clinical.yaml') as fh:
        yaml.dump(template, fh)


@dxpy.entry_point('main')
def main():
    """Main entry point for app"""
    dxpy.set_workspace_id(os.environ.get("DX_PROJECT_CONTEXT"))

    # get samplename and download vcf
    file = dxpy.DXFile(vcfs[0].get_id())
    file_name = file.describe()['name']
    file_prefix = file_name.replace('.vcf', '').replace('.gz', '')
    dxpy.download_dxfile(file, file_name)

    # split name and validate parts
    instrument_id, individual_id, clarity_id, epic_code, \
        sex, probeset = parse_samplename(file_name)

    # try parse caller from vcf header
    header = read_vcf_header(file_name)
    caller = infer_caller(header)

    # read in given  assay config and yaml templates
    clinical, individuals, manifest, samples = read_templates()
    config = json.loads(dxpy.DXFile('config').read())

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

    outfile = dxpy.upload_local_files(outname)
    return {'config_zip': dxpy.dxlink(outfile)}

dxpy.run()
