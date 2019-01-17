

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
PARTITIONED BY(year string, month string, day string)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe' LOCATION 's3://ellucian-clair-scan-results/'

#load a partition
ALTER TABLE reports ADD PARTITION (year='2019',month='01',day='15') location 's3://ellucian-clair-scan-results/2019/01/15/'
ALTER TABLE reports ADD PARTITION (year='2019',month='01',day='16') location 's3://ellucian-clair-scan-results/2019/01/16/'


select distinct ECRMetadata.registryId, ECRMetadata.repositoryName, ECRMetadata.imageId.imageDigest from reports where cardinality(vulnerabilities.High) > 0 and year='2019' and month='01' and day='15' order by ECRMetadata.registryId, ECRMetadata.repositoryName, ECRMetadata.imageId.imageDigest;


select distinct ECRMetadata.registryId, ECRMetadata.repositoryName, ECRMetadata.imageId.imageDigest from reports where cardinality(vulnerabilities.High) > 0 order by ECRMetadata.registryId, ECRMetadata.repositoryName, ECRMetadata.imageId.imageDigest;

