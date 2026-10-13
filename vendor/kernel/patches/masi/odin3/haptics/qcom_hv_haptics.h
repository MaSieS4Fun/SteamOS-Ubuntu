/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Copyright (c) 2024, Qualcomm Innovation Center, Inc. All rights reserved.
 */

#ifndef _QCOM_HV_HAPTICS_H
#define _QCOM_HV_HAPTICS_H

#include <linux/input.h>
#include <linux/remoteproc/qcom_rproc.h>
#include <linux/platform_device.h>

#if IS_ENABLED(CONFIG_INPUT_QCOM_HV_HAPTICS)
bool qcom_haptics_vi_sense_is_enabled(void);

int qcom_spmi_haptics_global_upload(struct ff_effect *effect);
int qcom_spmi_haptics_global_playback(int effect_id, int val);
int qcom_spmi_haptics_global_set_gain(u16 gain);
int qcom_spmi_haptics_global_stop(void);
#else
static inline bool qcom_haptics_vi_sense_is_enabled(void)
{
	return false;
}

static inline int qcom_spmi_haptics_global_upload(struct ff_effect *effect)
{
    return 0;
}

static inline int qcom_spmi_haptics_global_playback(int effect_id, int val)
{
    return 0;
}

static inline int qcom_spmi_haptics_global_set_gain(u16 gain)
{
    return 0;
}

static inline int qcom_spmi_haptics_global_stop(void)
{
    return 0;
}
#endif

#endif
