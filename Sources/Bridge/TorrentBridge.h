// Objective-C interface to libtorrent, imported into Swift as the bridging header.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RTTorrentStatus : NSObject
@property (nonatomic, copy) NSString *infoHash;
@property (nonatomic, copy) NSString *name;
/// One of: Downloading, Seeding, Paused, Queued, Checking, Metadata, Error
@property (nonatomic, copy) NSString *state;
@property (nonatomic, copy) NSString *errorMessage;
@property (nonatomic, copy) NSString *trackerStatus;
@property (nonatomic, copy) NSString *savePath;
@property (nonatomic, copy) NSArray<NSString *> *trackers;
@property (nonatomic, copy) NSArray<NSString *> *filePaths;
@property (nonatomic) double progress;          // 0...1
@property (nonatomic) int64_t downloadRate;     // bytes/s
@property (nonatomic) int64_t uploadRate;       // bytes/s
@property (nonatomic) int64_t totalWanted;      // bytes selected for download
@property (nonatomic) int64_t totalWantedDone;
@property (nonatomic) int64_t totalUploaded;    // all-time
@property (nonatomic) int64_t totalDownloaded;  // all-time
@property (nonatomic) int numPeers;
@property (nonatomic) int numSeeds;
@property (nonatomic) int queuePosition;
@property (nonatomic) BOOL hasMetadata;
@property (nonatomic) NSTimeInterval addedTime; // unix seconds
@end

@interface RTFileEntry : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic) int64_t size;
@property (nonatomic) int64_t downloaded;
@property (nonatomic) int priority;             // 0 = skip, 4 = normal, 7 = high
@end

@interface RTPeerEntry : NSObject
@property (nonatomic, copy) NSString *address;
@property (nonatomic, copy) NSString *client;
@property (nonatomic) double progress;
@property (nonatomic) int64_t downloadRate;
@property (nonatomic) int64_t uploadRate;
@end

@interface RTSession : NSObject

/// Starts libtorrent and restores torrents saved in `stateDirectory`.
- (instancetype)initWithStateDirectory:(NSString *)stateDirectory listenPort:(int)port;

- (nullable NSString *)addTorrentFile:(NSString *)path savePath:(NSString *)savePath
                                error:(NSError **)error;
- (nullable NSString *)addMagnet:(NSString *)uri savePath:(NSString *)savePath
                           error:(NSError **)error;

- (void)pause:(NSString *)infoHash;
- (void)resume:(NSString *)infoHash;
- (void)forceRecheck:(NSString *)infoHash;
- (void)remove:(NSString *)infoHash deleteFiles:(BOOL)deleteFiles;
- (void)setFilePriority:(NSString *)infoHash fileIndex:(int)index priority:(int)priority;

- (NSArray<RTTorrentStatus *> *)statuses;
- (NSArray<RTFileEntry *> *)filesFor:(NSString *)infoHash;
- (NSArray<RTPeerEntry *> *)peersFor:(NSString *)infoHash;

/// bytes/s; 0 means unlimited.
- (void)setDownloadLimit:(int)downloadBps uploadLimit:(int)uploadBps;
- (void)setListenPort:(int)port;
- (int)dhtNodes;

/// Handle pending libtorrent events (tracker replies, resume data, errors).
/// Call regularly from the main thread.
- (void)processAlerts;
/// Ask every torrent with unsaved changes to write resume data.
- (void)saveResumeDataAsync;
/// Write resume data for every torrent and stop the session. Blocks up to ~10 s.
- (void)shutdown;

@end

NS_ASSUME_NONNULL_END
