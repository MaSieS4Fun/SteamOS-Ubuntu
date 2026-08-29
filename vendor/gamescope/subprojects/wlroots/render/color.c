#include <assert.h>
#include <stdlib.h>
#include <wlr/render/color.h>
#include "render/color.h"

struct wlr_color_transform *wlr_color_transform_init_srgb(void) {
	struct wlr_color_transform *tx = calloc(1, sizeof(struct wlr_color_transform));
	if (!tx) {
		return NULL;
	}
	tx->type = COLOR_TRANSFORM_SRGB;
	tx->ref_count = 1;
	wlr_addon_set_init(&tx->addons);
	return tx;
}

static void color_transform_destroy(struct wlr_color_transform *tr) {
	free(tr->lut3d.lut_3d);
	wlr_addon_set_finish(&tr->addons);
	free(tr);
}

void wlr_color_transform_ref(struct wlr_color_transform *tr) {
	tr->ref_count += 1;
}

void wlr_color_transform_unref(struct wlr_color_transform *tr) {
	if (!tr) {
		return;
	}
	assert(tr->ref_count > 0);
	tr->ref_count -= 1;
	if (tr->ref_count == 0) {
		color_transform_destroy(tr);
	}
}
