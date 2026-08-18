/// Silo's engine: sources on one side, targets on the other, a deduplicated
/// content-addressed store in the middle.
///
/// The three layers know nothing about each other. Adding a mirror means
/// writing a [ModelSource]; adding a tool means writing a [DownloadTarget];
/// neither requires touching [ChunkedDownloader], which only moves bytes from
/// a URL into a file and has no idea what a model is.
library;

export 'src/download/chunked_downloader.dart'
    show ChunkedDownloader, DownloadHandle, DownloadOptions;
export 'src/download/download_types.dart'
    show
        ChecksumMismatchException,
        DownloadException,
        DownloadOutcome,
        DownloadProgress,
        StalePartException;
export 'src/download/http_probe.dart' show RemoteFileProbe, probeRemoteFile;
export 'src/download/part_file.dart' show PartFile;
export 'src/download/rate_limiter.dart' show RateLimiter;
export 'src/library.dart'
    show AddHandle, AddProgress, AddResult, SiloLibrary, UnlinkResult;
export 'src/model/model_ref.dart' show ModelRef;
export 'src/model/model_variant.dart'
    show ModelFormat, ModelVariant, groupVariants, isShardSetComplete;
export 'src/model/remote_file.dart' show ModelListing, RemoteFile;
export 'src/queue/download_queue.dart' show DownloadQueue;
export 'src/queue/queue_job.dart' show QueueJob, QueueJobStatus;
export 'src/source/huggingface_source.dart' show HuggingFaceSource;
export 'src/source/model_source.dart'
    show HttpModelSource, ModelNotFoundException, ModelSource;
export 'src/source/modelscope_source.dart' show ModelScopeSource;
export 'src/source/source_race.dart'
    show ResolvedSource, SourceSpeed, raceSources, resolveSources;
export 'src/store/blob_store.dart'
    show BlobStore, LinkMethod, LinkResult, inodeIdOf, linkCountOf;
export 'src/store/catalog.dart'
    show Catalog, CatalogEntry, CatalogFile, LinkRecord;
export 'src/target/download_target.dart'
    show DownloadTarget, InstallResult, TargetFile;
export 'src/target/lmstudio_target.dart' show InstalledModel, LmStudioTarget;
export 'src/util/sha256.dart' show Sha256, sha256OfFile, sha256OfFileDart;
