// Preprocessing
include { PREPARE_DROP as PREPARE_DROP_FRASER } from './modules/prepare_drop'
include { PREPARE_DROP as PREPARE_DROP_OUTRIDER } from './modules/prepare_drop'

// Annotations
include { ADD_CADD_SCORES_TO_VCF } from './modules/annotate/add_cadd_scores_to_vcf.nf'
include { ANNOTATE_VEP } from './modules/annotate/annotate_vep.nf'
include { CALCULATE_INDEL_CADD } from './modules/annotate/calculate_indel_cadd.nf'
include { CREATE_PED } from './modules/annotate/create_ped.nf'
include { EXTRACT_INDELS_FOR_CADD } from './modules/annotate/extract_indels_for_cadd.nf'
include { INDEL_VEP } from './modules/annotate/indel_vep.nf'
include { MARK_SPLICE } from './modules/annotate/mark_splice.nf'
include { MODIFY_VCF } from './modules/annotate/modify_vcf.nf'
include { VCF_ANNO } from './modules/annotate/vcf_anno.nf'
include { VCF_COMPLETION } from './modules/annotate/vcf_completion.nf'

// Genmod
include { GENMOD_ANNOTATE } from './modules/genmod/genmod_annotate.nf'
include { GENMOD_MODELS } from './modules/genmod/genmod_models.nf'
include { GENMOD_SCORE } from './modules/genmod/genmod_score.nf'
include { GENMOD_COMPOUND } from './modules/genmod/genmod_compound.nf'

// Postprocessing
include { FILTER_VARIANTS_ON_SCORE } from './modules/postprocessing/filter_variants_on_score.nf'
include { PARSE_TOMTE_QC } from './modules/postprocessing/parse_tomte_qc.nf'
include { MAKE_SCOUT_YAML } from './modules/postprocessing/make_scout_yaml.nf'

// OK some thinking
// In point is output from Tomte
// 1. SNV calls on RNA-seq
// 2. DROP results
// In reality the DROP results will be for a single sample, isn't it?
// We can maybe assume that pre-processing here

// OK, and now I can start with drafting the stub run


def assignDefaultParams(target_params, user_params) {
    target_params.each { param ->
        if (!user_params.containers.containsKey(param)) {
            user_params.containers[param] = null 
        }
    }
}

def validateParams(targetParams, search_scope, type) {
    def missingParams = targetParams.findAll { !search_scope[it] }
    if (!missingParams.isEmpty()) {
        def missingList = missingParams.collect { "--${it}" }.join(", ")
        error "Error: Missing required parameter(s) in $type: ${missingList}"
    }
}


def validateAllParams() {
    def containers = ['genmod', 'vep', 'ol_wgs']
    def vepParams = [
        'VEP_SYNONYMS',
        'VEP_FASTA',
        'VEP_CACHE',
        'VEP_PLUGINS',
        'VEP_TRANSCRIPT_DISTANCE',
        'CADD',
        'MAXENTSCAN',
        'DBNSFP',
        'GNOMAD_EXOMES',
        'GNOMAD_GENOMES',
        'GNOMAD_MT',
        'PHYLOP',
        'PHASTCONS'
    ]

    def otherParams = ['csv', 'score_thres', 'snv_calls']

    assignDefaultParams(containers, params)
    assignDefaultParams(vepParams, params)
    assignDefaultParams(otherParams, params)

    validateParams(otherParams, params, "base")
    validateParams(containers, params.containers, "containers")
    validateParams(vepParams, params.vep, "vep")
}

workflow  {

    validateAllParams()

    // FIXME: Check that the input CSV has only one line

    Channel
        .fromPath(params.csv)
        .splitCsv(header:true)
        .set { meta_ch }

    // vcf_ch = meta_ch.map { meta -> tuple(meta, params.variant_calls, params.variant_calls_tbi) }

    Channel
        .fromPath(params.hgnc_map)
        .set { hgnc_map_ch }

    Channel
        .fromPath(params.fraser_results)
        .set { fraser_results_ch }

    Channel
        .fromPath(params.outrider_results)
        .set { outrider_results_ch }

    preprocess(meta_ch, fraser_results_ch, outrider_results_ch, hgnc_map_ch)
        .set { fraser_out_ch }

    // Channel
    //     .of(tuple(params.cadd, params.cadd_tbi))
    //     .set { cadd_ch }

    // vcf_ch.view()

    // snv_annotate(vcf_ch, cadd_ch)

    // snv_score(vcf_ch.out.ped, vcf_ch.out.vcf, params.score_config)
}

workflow preprocess {
    take:
        ch_meta
        ch_fraser_results
        ch_outrider_results
        ch_hgnc_map
    main:
        PREPARE_DROP_FRASER(ch_meta, "FRASER", ch_fraser_results, ch_hgnc_map)
            .set { fraser_ch }

        PREPARE_DROP_OUTRIDER(ch_meta, "OUTRIDER", ch_outrider_results, ch_hgnc_map)
            .set { outrider_ch }

    emit:
        fraser_ch
        outrider_ch
}

workflow snv_annotate {
    take:
        ch_vcf  // channel: [mandatory] [ val(meta), path(vcf), path(vcf_tbi) ]
        ch_cadd // channel: [mandatory] [ path(cadd), path(cadd_tbi) ]

    main:

        CREATE_PED(ch_vcf[0])
            .set { ch_ped }

        // CADD indels
        EXTRACT_INDELS_FOR_CADD(ch_vcf)
        INDEL_VEP(ch_vcf).set { ch_vep_indels_only }
        CALCULATE_INDEL_CADD(ch_vep_indels_only).set { ch_cadd_indels }

        ANNOTATE_VEP(ch_vcf).set { ch_vep }
        VCF_ANNO(ch_vep).set { ch_vcf_anno }
        MODIFY_VCF(ch_vcf_anno).set { ch_scout_modified }
        MARK_SPLICE(ch_scout_modified).set { ch_mark_splice }

        ADD_CADD_SCORES_TO_VCF(ch_mark_splice, ch_cadd).set { ch_vcf_with_cadd }
        VCF_COMPLETION(ch_vcf_with_cadd).set { ch_vcf_completed }
    
    emit:
        ped = ch_ped
        vcf = ch_vcf
}

workflow snv_score {

    take:
        ch_annotated_vcf // channel: [mandatory] [ val(meta), path(vcf), path(vcf_tbi) ]
        ch_ped // channel: [mandatory] [ path(ped) ]
        ch_score_config // channel: [mandatory] [ path(score_config) ]
    
    main:
        GENMOD_MODELS(ch_annotated_vcf, ch_ped).set { ch_genmod_models }
        GENMOD_ANNOTATE(ch_genmod_models).set { ch_genmod_annotate }
        GENMOD_COMPOUND(ch_genmod_annotate).set { ch_genmod_compound }
        GENMOD_SCORE(ch_genmod_compound, ch_ped, ch_score_config).set { ch_genmod_score }
    
    emit:
        ch_genmod_score
}

workflow postprocess {
    take:
        scored_vcf_ch
        csv_ch
        multiqc_ch // Both general stats and the picard
    
    main:
        FILTER_VARIANTS_ON_SCORE(scored_vcf_ch, params.score_threshold)

        MAKE_SCOUT_YAML(csv_ch)
            .set { after_hello_ch }

        PARSE_TOMTE_QC(multiqc_ch)
        
    emit:
        after_hello_ch
}

