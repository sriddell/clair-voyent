select ECRMetadata.registryId, ECRMetadata.repositoryName, ECRMetadata.imageId.imageDigest from reports where cardinality(vulnerabilities.High) > 0;

CREATE external TABLE reports (
         LayerCount int,
AnalyzedImageName string,
  ImageDigest string,
  ECRMetadata struct<
  imageId:struct<imageDigest:string>,
  manifest:struct<config:struct<digest:string>>,
  repositoryName:string,
  registryId:string
>,

         Vulnerabilities struct< High:array<struct<Name:string,
         NamespaceName:string,
         Description:string,
         Link:string,
         Severity:string>>,
         Medium:array<struct<Name:string,
         NamespaceName:string,
         Description:string,
         Link:string,
         Severity:string>>,
         Medium:array<struct<Name:string,
         NamespaceName:string,
         Description:string,
         Link:string,
         Severity:string>>,
         Medium:array<struct<Name:string,
         NamespaceName:string,
         Description:string,
         Link:string,
         Severity:string>>,
         Low:array<struct<Name:string,
         NamespaceName:string,
         Description:string,
         Link:string,
         Severity:string>>,
         Medium:array<struct<Name:string,
         NamespaceName:string,
         Description:string,
         Link:string,
         Severity:string>>,
         Negligible:array<struct<Name:string,
         NamespaceName:string,
         Description:string,
         Link:string,
         Severity:string>>,
         Medium:array<struct<Name:string,
         NamespaceName:string,
         Description:string,
         Link:string,
         Severity:string>>
          >
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe' LOCATION 's3://ellucian-clair-scan-results/'



select ECRMetadata.registryId, ECRMetadata.repositoryName, ECRMetadata.imageId.imageDigest, cardinality(vulnerabilities.High) from reports where cardinality(vulnerabilities.High) > 0;

select ECRMetadata.registryId, ECRMetadata.repositoryName, ECRMetadata.imageId.imageDigest, cardinality(vulnerabilities.High) as high from reports where cardinality(vulnerabilities.High) > 0 order by high desc;