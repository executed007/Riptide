// libtorrent-rasterbar 2.x bridge. All methods are called from the main thread.
#import "TorrentBridge.h"

#include <libtorrent/session.hpp>
#include <libtorrent/session_params.hpp>
#include <libtorrent/session_stats.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/load_torrent.hpp>
#include <libtorrent/read_resume_data.hpp>
#include <libtorrent/write_resume_data.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/peer_info.hpp>
#include <libtorrent/announce_entry.hpp>
#include <libtorrent/fingerprint.hpp>

#include <chrono>
#include <fstream>
#include <memory>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

namespace lt = libtorrent;

@implementation RTTorrentStatus @end
@implementation RTFileEntry @end
@implementation RTPeerEntry @end

static NSString *NS(std::string const &s) {
    NSString *r = [NSString stringWithUTF8String:s.c_str()];
    if (!r) r = [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSISOLatin1StringEncoding];
    return r ?: @"";
}

static std::string hashString(lt::info_hash_t const &ih) {
    std::stringstream ss;
    ss << ih.get_best();
    return ss.str();
}

static NSError *makeError(NSString *message) {
    return [NSError errorWithDomain:@"Riptide" code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static bool readFile(std::string const &path, std::vector<char> &out) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return false;
    out.assign(std::istreambuf_iterator<char>(f), std::istreambuf_iterator<char>());
    return true;
}

static void writeFileAtomically(std::string const &path, std::vector<char> const &buf) {
    std::string tmp = path + ".tmp";
    {
        std::ofstream f(tmp, std::ios::binary | std::ios::trunc);
        f.write(buf.data(), static_cast<std::streamsize>(buf.size()));
    }
    std::rename(tmp.c_str(), path.c_str());
}

@implementation RTSession {
    std::unique_ptr<lt::session> _ses;
    std::string _stateDir;
    std::unordered_map<std::string, lt::torrent_handle> _handles;
    std::unordered_map<std::string, std::string> _trackerStatus;
    std::unordered_map<std::string, std::vector<std::string>> _fileCache;
    int _outstandingResume;
    int _dhtNodes;
    int _dhtMetric;
    int _tick;
}

- (std::string)resumePathFor:(std::string const &)hash {
    return _stateDir + "/" + hash + ".resume";
}

- (instancetype)initWithStateDirectory:(NSString *)stateDirectory listenPort:(int)port {
    if (!(self = [super init])) return nil;
    _stateDir = stateDirectory.UTF8String;
    [[NSFileManager defaultManager] createDirectoryAtPath:stateDirectory
                              withIntermediateDirectories:YES attributes:nil error:nil];
    _dhtMetric = lt::find_metric_idx("dht.dht_nodes");

    lt::session_params params;
    std::vector<char> stateBuf;
    if (readFile(_stateDir + "/session.state", stateBuf)) {
        try { params = lt::read_session_params(stateBuf, lt::session_handle::save_dht_state); }
        catch (...) {}
    }
    lt::settings_pack &sp = params.settings;
    sp.set_int(lt::settings_pack::alert_mask,
               lt::alert_category::error | lt::alert_category::status |
               lt::alert_category::storage | lt::alert_category::tracker);
    std::string iface = "0.0.0.0:" + std::to_string(port) + ",[::]:" + std::to_string(port);
    sp.set_str(lt::settings_pack::listen_interfaces, iface);
    sp.set_str(lt::settings_pack::user_agent, "Riptide/1.0 libtorrent/" LIBTORRENT_VERSION);
    sp.set_str(lt::settings_pack::peer_fingerprint, lt::generate_fingerprint("RT", 1, 0, 0, 0));
    sp.set_bool(lt::settings_pack::enable_dht, true);
    sp.set_bool(lt::settings_pack::enable_lsd, true);
    sp.set_bool(lt::settings_pack::enable_upnp, true);
    sp.set_bool(lt::settings_pack::enable_natpmp, true);
    sp.set_int(lt::settings_pack::active_downloads, 8);
    sp.set_int(lt::settings_pack::active_seeds, 10);
    sp.set_int(lt::settings_pack::active_limit, 30);
    _ses = std::make_unique<lt::session>(std::move(params));

    // Restore saved torrents.
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:stateDirectory error:nil];
    for (NSString *name in names) {
        if (![name hasSuffix:@".resume"]) continue;
        std::vector<char> buf;
        if (!readFile(_stateDir + "/" + name.UTF8String, buf)) continue;
        lt::error_code ec;
        lt::add_torrent_params p = lt::read_resume_data(buf, ec);
        if (ec) continue;
        _ses->async_add_torrent(std::move(p));
    }
    return self;
}

- (void)track:(lt::torrent_handle const &)h {
    std::string hash = hashString(h.info_hashes());
    _handles[hash] = h;
    h.save_resume_data(lt::torrent_handle::save_info_dict);
    _outstandingResume++;
}

- (nullable NSString *)addParams:(lt::add_torrent_params)p savePath:(NSString *)savePath
                           error:(NSError **)error {
    p.save_path = savePath.UTF8String;
    p.flags |= lt::torrent_flags::duplicate_is_error;
    lt::error_code ec;
    lt::torrent_handle h = _ses->add_torrent(std::move(p), ec);
    if (ec) {
        if (error) *error = makeError(ec == lt::errors::duplicate_torrent
                                      ? @"This torrent is already in the list."
                                      : NS(ec.message()));
        return nil;
    }
    [self track:h];
    return NS(hashString(h.info_hashes()));
}

- (nullable NSString *)addTorrentFile:(NSString *)path savePath:(NSString *)savePath
                                error:(NSError **)error {
    lt::add_torrent_params p;
    try { p = lt::load_torrent_file(path.UTF8String); }
    catch (std::exception const &e) {
        if (error) *error = makeError([NSString stringWithFormat:@"Not a valid .torrent file: %@", NS(e.what())]);
        return nil;
    }
    return [self addParams:std::move(p) savePath:savePath error:error];
}

- (nullable NSString *)addMagnet:(NSString *)uri savePath:(NSString *)savePath
                           error:(NSError **)error {
    lt::error_code ec;
    lt::add_torrent_params p = lt::parse_magnet_uri(uri.UTF8String, ec);
    if (ec) {
        if (error) *error = makeError([NSString stringWithFormat:@"Not a valid magnet link: %@", NS(ec.message())]);
        return nil;
    }
    return [self addParams:std::move(p) savePath:savePath error:error];
}

- (lt::torrent_handle)handleFor:(NSString *)infoHash {
    auto it = _handles.find(infoHash.UTF8String);
    return it == _handles.end() ? lt::torrent_handle() : it->second;
}

- (void)pause:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (!h.is_valid()) return;
    h.unset_flags(lt::torrent_flags::auto_managed);
    h.pause(lt::torrent_handle::graceful_pause);
}

- (void)resume:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (!h.is_valid()) return;
    h.clear_error();
    h.set_flags(lt::torrent_flags::auto_managed);
    h.resume();
}

- (void)forceRecheck:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (h.is_valid()) h.force_recheck();
}

- (void)remove:(NSString *)infoHash deleteFiles:(BOOL)deleteFiles {
    std::string hash = infoHash.UTF8String;
    lt::torrent_handle h = [self handleFor:infoHash];
    if (h.is_valid()) {
        _ses->remove_torrent(h, deleteFiles ? lt::session_handle::delete_files : lt::remove_flags_t{});
    }
    _handles.erase(hash);
    _trackerStatus.erase(hash);
    _fileCache.erase(hash);
    std::remove([self resumePathFor:hash].c_str());
}

- (void)setFilePriority:(NSString *)infoHash fileIndex:(int)index priority:(int)priority {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (!h.is_valid()) return;
    h.file_priority(lt::file_index_t(index), lt::download_priority_t(static_cast<std::uint8_t>(priority)));
}

- (NSArray<RTTorrentStatus *> *)statuses {
    NSMutableArray *out = [NSMutableArray array];
    for (auto &[hash, h] : _handles) {
        if (!h.is_valid()) continue;
        lt::torrent_status st = h.status(lt::torrent_handle::query_name | lt::torrent_handle::query_save_path);
        RTTorrentStatus *s = [RTTorrentStatus new];
        s.infoHash = NS(hash);
        s.name = st.name.empty() ? NS(hash) : NS(st.name);
        s.savePath = NS(st.save_path);
        s.progress = st.progress;
        s.downloadRate = st.download_payload_rate;
        s.uploadRate = st.upload_payload_rate;
        s.totalWanted = st.total_wanted;
        s.totalWantedDone = st.total_wanted_done;
        s.totalUploaded = st.all_time_upload;
        s.totalDownloaded = st.all_time_download;
        s.numPeers = st.num_peers;
        s.numSeeds = st.num_seeds;
        s.queuePosition = static_cast<int>(st.queue_position);
        s.hasMetadata = st.has_metadata;
        s.addedTime = static_cast<NSTimeInterval>(st.added_time);
        s.errorMessage = st.errc ? NS(st.errc.message()) : @"";

        bool paused = bool(st.flags & lt::torrent_flags::paused);
        bool autoManaged = bool(st.flags & lt::torrent_flags::auto_managed);
        NSString *state;
        if (st.errc) state = @"Error";
        else if (paused) state = autoManaged ? @"Queued" : @"Paused";
        else switch (st.state) {
            case lt::torrent_status::checking_files:
            case lt::torrent_status::checking_resume_data: state = @"Checking"; break;
            case lt::torrent_status::downloading_metadata: state = @"Metadata"; break;
            case lt::torrent_status::downloading: state = @"Downloading"; break;
            default: state = @"Seeding"; break;
        }
        s.state = state;
        if (paused) {  // libtorrent's rates are moving averages; show 0 once paused
            s.downloadRate = 0;
            s.uploadRate = 0;
        }

        auto ts = _trackerStatus.find(hash);
        s.trackerStatus = ts == _trackerStatus.end() ? @"" : NS(ts->second);

        NSMutableArray *trackers = [NSMutableArray array];
        for (auto const &ae : h.trackers()) [trackers addObject:NS(ae.url)];
        s.trackers = trackers;

        auto &files = _fileCache[hash];
        if (files.empty() && st.has_metadata) {
            if (auto tf = h.torrent_file()) {
                auto const &fs = tf->layout();
                for (auto i : fs.file_range()) files.push_back(fs.file_path(i));
            }
        }
        NSMutableArray *paths = [NSMutableArray arrayWithCapacity:files.size()];
        for (auto const &f : files) [paths addObject:NS(f)];
        s.filePaths = paths;
        [out addObject:s];
    }
    return out;
}

- (NSArray<RTFileEntry *> *)filesFor:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (!h.is_valid()) return @[];
    auto tf = h.torrent_file();
    if (!tf) return @[];
    auto const &fs = tf->layout();
    std::vector<std::int64_t> progress = h.file_progress(lt::torrent_handle::piece_granularity);
    std::vector<lt::download_priority_t> prios = h.get_file_priorities();
    NSMutableArray *out = [NSMutableArray array];
    for (auto i : fs.file_range()) {
        int idx = static_cast<int>(i);
        RTFileEntry *e = [RTFileEntry new];
        e.path = NS(fs.file_path(i));
        e.size = fs.file_size(i);
        e.downloaded = idx < (int)progress.size() ? progress[idx] : 0;
        e.priority = idx < (int)prios.size() ? static_cast<int>(static_cast<std::uint8_t>(prios[idx])) : 4;
        [out addObject:e];
    }
    return out;
}

- (NSArray<RTPeerEntry *> *)peersFor:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (!h.is_valid()) return @[];
    std::vector<lt::peer_info> peers;
    h.get_peer_info(peers);
    NSMutableArray *out = [NSMutableArray array];
    for (auto const &p : peers) {
        RTPeerEntry *e = [RTPeerEntry new];
        auto ep = p.remote_endpoint();
        e.address = NS(ep.address().to_string() + ":" + std::to_string(ep.port()));
        e.client = NS(p.client);
        e.progress = p.progress;
        e.downloadRate = p.payload_down_speed;
        e.uploadRate = p.payload_up_speed;
        [out addObject:e];
    }
    return out;
}

- (void)setDownloadLimit:(int)downloadBps uploadLimit:(int)uploadBps {
    lt::settings_pack sp;
    sp.set_int(lt::settings_pack::download_rate_limit, downloadBps);
    sp.set_int(lt::settings_pack::upload_rate_limit, uploadBps);
    _ses->apply_settings(std::move(sp));
}

- (void)setListenPort:(int)port {
    lt::settings_pack sp;
    std::string iface = "0.0.0.0:" + std::to_string(port) + ",[::]:" + std::to_string(port);
    sp.set_str(lt::settings_pack::listen_interfaces, iface);
    _ses->apply_settings(std::move(sp));
}

- (int)dhtNodes { return _dhtNodes; }

- (void)processAlerts {
    if (!_ses) return;
    if (++_tick % 5 == 0) _ses->post_session_stats();
    std::vector<lt::alert *> alerts;
    _ses->pop_alerts(&alerts);
    for (lt::alert *a : alerts) {
        if (auto *aa = lt::alert_cast<lt::add_torrent_alert>(a)) {
            if (!aa->error && aa->handle.is_valid()) {
                std::string hash = hashString(aa->handle.info_hashes());
                if (!_handles.count(hash)) _handles[hash] = aa->handle;
            }
        } else if (auto *ra = lt::alert_cast<lt::save_resume_data_alert>(a)) {
            std::string hash = hashString(ra->params.info_hashes);
            if (_handles.count(hash)) writeFileAtomically([self resumePathFor:hash], lt::write_resume_data_buf(ra->params));
            if (_outstandingResume > 0) _outstandingResume--;
        } else if (lt::alert_cast<lt::save_resume_data_failed_alert>(a)) {
            if (_outstandingResume > 0) _outstandingResume--;
        } else if (auto *fa = lt::alert_cast<lt::torrent_finished_alert>(a)) {
            fa->handle.save_resume_data(lt::torrent_handle::save_info_dict);
            _outstandingResume++;
        } else if (auto *ma = lt::alert_cast<lt::metadata_received_alert>(a)) {
            ma->handle.save_resume_data(lt::torrent_handle::save_info_dict);
            _outstandingResume++;
        } else if (auto *tr = lt::alert_cast<lt::tracker_reply_alert>(a)) {
            _trackerStatus[hashString(tr->handle.info_hashes())] = "Announce OK";
        } else if (auto *te = lt::alert_cast<lt::tracker_error_alert>(a)) {
            // "skipping tracker announce (unreachable)": an endpoint (e.g. IPv6) this
            // machine can't reach. Not a real tracker failure, so don't report it.
            if (te->error == lt::errors::announce_skipped) continue;
            std::string msg = te->failure_reason();
            if (msg.empty()) msg = te->error.message();
            _trackerStatus[hashString(te->handle.info_hashes())] = "Error: " + msg;
        } else if (auto *tw = lt::alert_cast<lt::tracker_warning_alert>(a)) {
            _trackerStatus[hashString(tw->handle.info_hashes())] = std::string("Warning: ") + tw->warning_message();
        } else if (auto *ta = lt::alert_cast<lt::tracker_announce_alert>(a)) {
            std::string hash = hashString(ta->handle.info_hashes());
            if (!_trackerStatus.count(hash)) _trackerStatus[hash] = "Announce Sent";
        } else if (auto *ss = lt::alert_cast<lt::session_stats_alert>(a)) {
            if (_dhtMetric >= 0) _dhtNodes = static_cast<int>(ss->counters()[_dhtMetric]);
        }
    }
}

- (void)saveResumeDataAsync {
    for (auto &[hash, h] : _handles) {
        if (!h.is_valid()) continue;
        h.save_resume_data(lt::torrent_handle::save_info_dict | lt::torrent_handle::only_if_modified);
    }
}

- (void)shutdown {
    if (!_ses) return;
    _ses->pause();
    _outstandingResume = 0;
    for (auto &[hash, h] : _handles) {
        if (!h.is_valid()) continue;
        h.save_resume_data(lt::torrent_handle::save_info_dict);
        _outstandingResume++;
    }
    auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
    while (_outstandingResume > 0 && std::chrono::steady_clock::now() < deadline) {
        _ses->wait_for_alert(std::chrono::milliseconds(250));
        [self processAlerts];
    }
    try {
        writeFileAtomically(_stateDir + "/session.state",
                            lt::write_session_params_buf(_ses->session_state(lt::session_handle::save_dht_state),
                                                         lt::session_handle::save_dht_state));
    } catch (...) {}
    _ses.reset();
}

@end
