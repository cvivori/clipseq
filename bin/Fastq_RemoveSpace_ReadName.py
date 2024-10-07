#!/usr/bin/env python

import argparse
import pandas as pd
import os; # to execute shell commands
import sys# to execute shell commands and process outputs
import gzip

parser = argparse.ArgumentParser(description='Add space that Ultraplex removes from <y-pos> and <read> in the read name.')
parser.add_argument('input_fastq', metavar='Input_fastq', type=str, ##nargs='+': all command-line args present are gathered into a list + error message if empty
                    help='Input fastq files, whose read name has to be fixed')
# parser.add_argument('-o','--out', dest='Folder_out', type=str, required=False,
#                     help='Output folder')
args = parser.parse_args() ## Namespace object, call as a dictionary: vars(args)


## If OUT FOLDER is not defined, create it
# # if args.Folder_out is not None:
# # 	out_folder = args.Folder_out
# # else:
# # 	out_folder =  "Fixed_fastq"
# # 	cmd_makeout = "mkdir " + out_folder
# # 	os.system(cmd_makeout)
# print ("--- Output folder:\t",out_folder)




print("--- Analyzing fastq files:")
f = os.path.basename(args.input_fastq)


## extract file name without extension
split_fq = f.split(".")
length = len(split_fq)
name = ".".join(split_fq[0:(length-2)]) 
extension = ".".join(split_fq[(length-2):(length)])
fixed_name = name + "_fixed"
input_fastq = args.input_fastq
output_fastq = fixed_name + "." + extension

# print(extension)
if os.path.exists(output_fastq):
	print("\t",output_fastq," exists")
else:
	if extension in ('fq.gz', 'fastq.gz'):
		print("\t",f)

	# input_fastq = '/nemo/lab/vanwervenf/home/users/vivoric/aTSS-project/timecourse_2023/TSSseq/TSSseq_4SU_paraclu50_pe/test.fastq.gz'
	# output_fastq = '/nemo/lab/vanwervenf/home/users/vivoric/aTSS-project/timecourse_2023/TSSseq/TSSseq_4SU_paraclu50_pe/test_out.fastq.gz'

		with gzip.open(input_fastq, 'rt') as infile, gzip.open(output_fastq, 'wt') as outfile:
			while True:
				# Read 4 lines at a time (FASTQ format block)
				header = infile.readline().strip()  # Read name (header line)
				if not header:
					break  # End of file
				sequence = infile.readline().strip()  # Sequence
				plus_line = infile.readline().strip()  # "+" separator line
				quality = infile.readline().strip()  # Quality score

				# Check if the header contains <y-pos><read> without a space, and insert the space
				if header.startswith('@'):
					header = header.replace(' ', '')

				# Write modified read to output file
				outfile.write(f"{header}\n{sequence}\n{plus_line}\n{quality}\n")

	else:
		print("\t(",f,") ignored")


