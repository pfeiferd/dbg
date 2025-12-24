
[comment]: # (“Commons Clause” License Condition v1.0)
[comment]: # ()  
[comment]: # (The Software is provided to you by the Licensor under the License,)
[comment]: # (as defined below, subject to the following condition.)
[comment]: # ()  
[comment]: # (Without limiting other conditions in the License, the grant of rights under the License)
[comment]: # (will not include, and the License does not grant to you, the right to Sell the Software.)
[comment]: # ()
[comment]: # (For purposes of the foregoing, “Sell” means practicing any or all of the rights granted)
[comment]: # (to you under the License to provide to third parties, for a fee or other consideration)
[comment]: # (including without limitation fees for hosting or consulting/ support services related to)
[comment]: # (the Software, a product or service whose value derives, entirely or substantially, from the)
[comment]: # (functionality of the Software. Any license notice or attribution required by the License)
[comment]: # (must also include this Commons Clause License Condition notice.)
[comment]: # ()
[comment]: # (Software: genestrip-ft)
[comment]: # ()
[comment]: # (License: Apache 2.0)
[comment]: # ()
[comment]: # (Licensor: Daniel Pfeifer, daniel.pfeifer@progotec.de)

**Genestrip-FT**: Optimizing Genestrip's *k*-mer databases for acccuracy on the genus level
===============================================

## Introduction

Genestrip-FT is an extension of [Genestrip](https://github.com/pfeiferd/genestrip), so most of its functionality is inherited from
Genestrip. Please consult [Genestrip's documentation]() before dealing with this project.

Genestrip-FT addresses a major problem
of *k*-mer databases under the genus rank: Due to the lowest common ancestor update (LCA update) for each stored *k*-mer, a *k*-mer 
is pushed to the genus already if it is shared by just two species subordinate to that genus.
As a result, a *k*-mer database's accuracy tends to descrease when used for metagenomic analysis given that the collection
of genomes used for the LCA update is large. This effect has been studied extensively in []().

Genestrip-FT addresses this problem by *refining the taxonomy tree* as included in a Genestrip database via the following steps:
1) It performs an analysis for each *k*-mer stored right under the genus rank to determine from which species it was pushed up as part of the
LCA update that happened when the database was built (via the goal `kmerindexbloom`). 
2) After collecting statistics on all related *k*-mers it computes a degree of intersection between
any two species that belong to the same genus using the Jaccard-index (via the goal `intersectcount`). The intersection is computed via the number
of joint *k*-mers between such two species as stored right under the genus rank.
3) The Jaccard-indices of any two species under the same genus form a symmetric real-valued matrix. The matrix forms a similarity measure for species that aids to compute a dendrogram via agglomerative clustering
using single linkage as the cluster distance (based on the goal `dendrogram`). 
4) The tree included in the dendrogram is used
to refine the actual taxonomy tree as stored along with the database. In addition, the *k*-mers originally assigned to 
the genus are pushed down to their according nodes in the refined taxonomy tree (both via the goal `updatestore`).
5) Finally, the reworked Genestrip database gets stored and can then be used for improved metagenomic analysis (via the goal `ftdb`).

## License

[Like Genestrip itself, Genestrip-FT is free for non-commercial use.](./LICENSE.txt) Please contact [daniel.pfeifer@progotec.de](mailto:daniel.pfeifer@progotec.de) if you are interested in a commercial license.

## Building and installing

Genestrip-FT is structured as a standard [Maven 2 or 3](https://maven.apache.org/) project and is compatible with the [JDK](https://jdk.java.net/) 11 or higher.[^1]

To build it, `cd` to the installation directory `genestrip-ft`. Given a matching Maven and JDK installation, `mvn install` will compile and install the Genestrip-FT program library. Afterwards a self-contained and executable `genestrip-ft.jar` file will be stored under `./lib`. 

## Technical documentation

### Usage and goals

The usage of Genestrip:
```
usage: genestrip-ft [options] <project> [<goal1> <goal2>...]
 -C <key>=<value>           To set Genestrip configuration paramaters via
                            the command line.
 -d <base dir>              Base directory for all data files. The default
                            is './data'.
 -db <database>             Path to filtering or matching database for the
                            goals 'filter' or 'match', 'matchlr', 'dbinfo'
                            and 'db2fastq' for use without project
                            context.
 -f <fqfile1,fqfile2,...>   Input fastq files as paths or URLs to be
                            processed via the goals 'filter', 'match' or
                            'matchlr'. When a URL is given, the fastq file
                            will not be downloaded but data streaming will
                            be applied unless '-l' or '-ll' is given.
 -k <key>                   Key used as a prefix for naming result files
                            in conjuntion with '-f'.
 -l                         Download fastqs from URLs to '<base
                            dir>/projects/<project name>/fastq' instead of
                            streaming them for the goals 'filter', 'match'
                            and 'matchlr'.
 -ll                        Download fastqs from URLs to '<base
                            dir>/fastq' instead of streaming them for the
                            goals 'filter', 'match' and 'matchlr'.
 -m <fqmap>                 Mapping file with a list of fastq files to be
                            processed via the goals 'filter', 'match' or
                            'matchlr'. Each line of the file must have the
                            format '<key> <URL or path to fastq file>'.
 -r <path>                  Common store folder for filtered fastq files
                            and result files created via the goals
                            'filter', 'match' or 'matchlr'. The defaults
                            are '<base dir>/projects/<project name>/fastq'
                            and '<base dir>/projects/<project name>/csv',
                            respectively.
 -t <target>                Generation target ('make', 'clean' or
                            'cleanall'). The default is 'make'.
 -tx <taxids>               List of tax ids separated by ',' (but no
                            blanks) for the goal 'db2fastq'. A tax id may
                            have the suffix '+', which means that
                            taxonomic descendants from the project's
                            database will be included.
 -v                         Print version.                            
```

### Additional goals

[**This is a list of all goals**](Goals.md)
[in addition to the ones from Genestrip](https://github.com/pfeiferd/genestrip/blob/master/Goals.md).

The extended goal graph is shown below. Dashed boxes are goals inherited from Genestrip -
so this is where Genestrip-FT relies on Genestrip's respective implementations.
Please keep in mind that the entire graph is a union of the graph from below and [Genstrip's original goal graph](https://github.com/pfeiferd/genestrip/blob/master/GoalGraph.svg).

<p align="center">
  <img src="GoalGraph.svg" width="1400"/>
</p>

### Additional configuration parameters

[**This is a list of all configuration parameters**](ConfigParams.md)
[in addition to the ones from Genestrip](https://github.com/pfeiferd/genestrip/blob/master/ConfigParams.md).