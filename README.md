Home for CMD post processing pipeline for Tomte (https://github.com/genomic-medicine-sweden/tomte)

Takes the CSV-samplesheet used to run Tomte and and path to the Tomte results folder as input.

### Map HGNC symbol to ID

A two-column file mapping HGNC symbol to ID is currently needed, as this isn't performed by Tomte but required by Scout (`params.hgnc_map`).

Steps to prepare:

1. Download the latest tab `hgnc_complete_set` file from [https://www.genenames.org/download/archive/#!/#tocAnchor-1-3](genenames.org)
2. Extract the symbol and ID columns, without header

```
tail -n +2 hgnc_complete_set.txt | head | cut -f1,2 | sed "s/HGNC://" > hgnc_id_symbol_map.tsv
```
