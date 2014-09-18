## TODO planning for p5-Bio-SeqWare-Upload-CgHub-Bam.

# ROADMAP
These changes are planned for the release specified. Date and version indicate when they are expected to be released.
2014-09-10 0.000.003 [MAJOR] - Generate meta data.

# APPROVED / REJECTED
These changes are planned, or will NOT be done, but have not been assigned to a specific future release. Date and version indicate when they were moved from "In consideration". 

# IN CONSIDERATION
These are things we might do. Date and version indicate when they were added for consideration.

2014-09-02 0.000.001 [MAJOR] - Need to release initial version of this distro.
2014-09-02 0.000.001 [DOC] - Consider moving the main POD from the module to the executable file.
2014-09-18 0.000.001 [DOC] - Refactor get data subroutine into 4, one that does the
big query, and then passes that to three subroutines that generate the individual
data blocks for the individual xml runs. Reduces coupling, increases testability.