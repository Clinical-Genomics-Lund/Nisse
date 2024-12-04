process GENMOD_COMPOUND {

    tag "${meta.sample}"
	label "process_low"
	container "${params.containers.base}"

    input:
        tuple val(meta), path(vcf)

    output:
        tuple val(meta), path("*_compound.vcf"), emit: vcf

    script:
    """
    genmod \\
        compound \\
        --processes ${task.cpus} \\
        --outfile ${meta.sample}_compound.vcf \\
        ${vcf}
    """

    stub:
    """
    touch ${meta.sample}_compound.vcf
    """
}