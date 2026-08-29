#include <assert.h>
#include <xf86drm.h>
#include <stdlib.h>
#include <unistd.h>
#include <wayland-server-core.h>
#include <wlr/render/drm_syncobj.h>
#include <wlr/util/log.h>

#include "config.h"

#if HAVE_EVENTFD
#include <sys/eventfd.h>
#endif

struct wlr_drm_syncobj_timeline *wlr_drm_syncobj_timeline_create(int drm_fd) {
	struct wlr_drm_syncobj_timeline *timeline = calloc(1, sizeof(*timeline));
	if (timeline == NULL) {
		return NULL;
	}
	timeline->drm_fd = drm_fd;
	timeline->n_refs = 1;

	if (drmSyncobjCreate(drm_fd, 0, &timeline->handle) != 0) {
		wlr_log_errno(WLR_ERROR, "drmSyncobjCreate failed");
		free(timeline);
		return NULL;
	}

	return timeline;
}

struct wlr_drm_syncobj_timeline *wlr_drm_syncobj_timeline_import(int drm_fd,
		int drm_syncobj_fd) {
	struct wlr_drm_syncobj_timeline *timeline = calloc(1, sizeof(*timeline));
	if (timeline == NULL) {
		return NULL;
	}
	timeline->drm_fd = drm_fd;
	timeline->n_refs = 1;

	if (drmSyncobjFDToHandle(drm_fd, drm_syncobj_fd, &timeline->handle) != 0) {
		wlr_log_errno(WLR_ERROR, "drmSyncobjFDToHandle failed");
		free(timeline);
		return NULL;
	}

	return timeline;
}

struct wlr_drm_syncobj_timeline *wlr_drm_syncobj_timeline_ref(struct wlr_drm_syncobj_timeline *timeline) {
	timeline->n_refs++;
	return timeline;
}

void wlr_drm_syncobj_timeline_unref(struct wlr_drm_syncobj_timeline *timeline) {
	if (timeline == NULL) {
		return;
	}

	assert(timeline->n_refs > 0);
	timeline->n_refs--;
	if (timeline->n_refs > 0) {
		return;
	}

	drmSyncobjDestroy(timeline->drm_fd, timeline->handle);
	free(timeline);
}

int wlr_drm_syncobj_timeline_export_sync_file(struct wlr_drm_syncobj_timeline *timeline,
		uint64_t src_point) {
	int sync_file_fd = -1;

	uint32_t syncobj_handle;
	if (drmSyncobjCreate(timeline->drm_fd, 0, &syncobj_handle) != 0) {
		wlr_log_errno(WLR_ERROR, "drmSyncobjCreate failed");
		return -1;
	}

	if (drmSyncobjTransfer(timeline->drm_fd, syncobj_handle, 0,
			timeline->handle, src_point, 0) != 0) {
		wlr_log_errno(WLR_ERROR, "drmSyncobjTransfer failed");
		goto out;
	}

	if (drmSyncobjExportSyncFile(timeline->drm_fd,
			syncobj_handle, &sync_file_fd) != 0) {
		wlr_log_errno(WLR_ERROR, "drmSyncobjExportSyncFile failed");
		goto out;
	}

out:
	drmSyncobjDestroy(timeline->drm_fd, syncobj_handle);
	return sync_file_fd;
}

bool wlr_drm_syncobj_timeline_import_sync_file(struct wlr_drm_syncobj_timeline *timeline,
		uint64_t dst_point, int sync_file_fd) {
	bool ok = false;

	uint32_t syncobj_handle;
	if (drmSyncobjCreate(timeline->drm_fd, 0, &syncobj_handle) != 0) {
		wlr_log_errno(WLR_ERROR, "drmSyncobjCreate failed");
		return -1;
	}

	if (drmSyncobjImportSyncFile(timeline->drm_fd, syncobj_handle,
			sync_file_fd) != 0) {
		wlr_log_errno(WLR_ERROR, "drmSyncobjImportSyncFile failed");
		goto out;
	}

	if (drmSyncobjTransfer(timeline->drm_fd, timeline->handle, dst_point,
			syncobj_handle, 0, 0) != 0) {
		wlr_log_errno(WLR_ERROR, "drmSyncobjTransfer failed");
		goto out;
	}

	ok = true;

out:
	drmSyncobjDestroy(timeline->drm_fd, syncobj_handle);
	return ok;
}

bool wlr_drm_syncobj_timeline_check(struct wlr_drm_syncobj_timeline *timeline,
		uint64_t point, uint32_t flags, bool *result) {
	int etime;
#if defined(__FreeBSD__)
	etime = ETIMEDOUT;
#else
	etime = ETIME;
#endif

	uint32_t signaled_point;
	int ret = drmSyncobjTimelineWait(timeline->drm_fd, &timeline->handle, &point, 1, 0, flags, &signaled_point);
	if (ret != 0 && ret != -etime) {
		wlr_log_errno(WLR_ERROR, "drmSyncobjWait() failed");
		return false;
	}

	*result = ret == 0;
	return true;
}

static int handle_eventfd_ready(int ev_fd, uint32_t mask, void *data) {
	struct wlr_drm_syncobj_timeline_waiter *waiter = data;

	if (mask & (WL_EVENT_HANGUP | WL_EVENT_ERROR)) {
		wlr_log(WLR_ERROR, "Failed to wait for render timeline: eventfd error");
	}

	if (mask & WL_EVENT_READABLE) {
		uint64_t ev_fd_value;
		if (read(ev_fd, &ev_fd_value, sizeof(ev_fd_value)) <= 0) {
			wlr_log(WLR_ERROR, "Failed to wait for render timeline: read() failed");
		}
	}

	wl_signal_emit_mutable(&waiter->events.ready, NULL);
	return 0;
}

bool wlr_drm_syncobj_timeline_waiter_init(struct wlr_drm_syncobj_timeline_waiter *waiter,
		struct wlr_drm_syncobj_timeline *timeline, uint64_t point, uint32_t flags,
		struct wl_event_loop *loop) {
	int ev_fd;
#if HAVE_EVENTFD
	ev_fd = eventfd(0, EFD_CLOEXEC);
	if (ev_fd < 0) {
		wlr_log_errno(WLR_ERROR, "eventfd() failed");
	}
#else
	ev_fd = -1;
	wlr_log(WLR_ERROR, "eventfd() is unavailable");
#endif
	if (ev_fd < 0) {
		return NULL;
	}

	struct drm_syncobj_eventfd syncobj_eventfd = {
		.handle = timeline->handle,
		.flags = flags,
		.point = point,
		.fd = ev_fd,
	};
	if (drmIoctl(timeline->drm_fd, DRM_IOCTL_SYNCOBJ_EVENTFD, &syncobj_eventfd) != 0) {
		wlr_log_errno(WLR_ERROR, "DRM_IOCTL_SYNCOBJ_EVENTFD failed");
		close(ev_fd);
		return NULL;
	}

	struct wl_event_source *source = wl_event_loop_add_fd(loop, ev_fd, WL_EVENT_READABLE, handle_eventfd_ready, waiter);
	if (source == NULL) {
		wlr_log(WLR_ERROR, "Failed to add FD to event loop");
		close(ev_fd);
		return NULL;
	}

	*waiter = (struct wlr_drm_syncobj_timeline_waiter){
		.ev_fd = ev_fd,
		.event_source = source,
	};
	wl_signal_init(&waiter->events.ready);
	return true;
}

void wlr_drm_syncobj_timeline_waiter_finish(struct wlr_drm_syncobj_timeline_waiter *waiter) {
	wl_list_remove(&waiter->events.ready.listener_list);
	wl_event_source_remove(waiter->event_source);
	close(waiter->ev_fd);
}
