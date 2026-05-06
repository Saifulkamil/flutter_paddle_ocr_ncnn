// Tencent is pleased to support the open source community by making ncnn available.
//
// Copyright (C) 2025 THL A29 Limited, a Tencent company. All rights reserved.
//
// Licensed under the BSD 3-Clause License (the "License"); you may not use this file except
// in compliance with the License. You may obtain a copy of the License at
//
// https://opensource.org/licenses/BSD-3-Clause
//
// Unless required by applicable law or agreed to in writing, software distributed
// under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

#include <android/asset_manager_jni.h>
#include <android/native_window_jni.h>
#include <android/native_window.h>

#include <android/log.h>

#include <jni.h>

#include <string>
#include <vector>

#include <platform.h>
#include <benchmark.h>

#include "ppocrv5.h"

#include "ndkcamera.h"

#include <opencv2/core/core.hpp>
#include <opencv2/imgproc/imgproc.hpp>
#include <opencv2/highgui/highgui.hpp>

#include "ppocrv5_dict.h"

#if __ARM_NEON
#include <arm_neon.h>
#endif // __ARM_NEON

static int draw_unsupported(cv::Mat& rgb)
{
    const char text[] = "unsupported";

    int baseLine = 0;
    cv::Size label_size = cv::getTextSize(text, cv::FONT_HERSHEY_SIMPLEX, 1.0, 1, &baseLine);

    int y = (rgb.rows - label_size.height) / 2;
    int x = (rgb.cols - label_size.width) / 2;

    cv::rectangle(rgb, cv::Rect(cv::Point(x, y), cv::Size(label_size.width, label_size.height + baseLine)),
                    cv::Scalar(255, 255, 255), -1);

    cv::putText(rgb, text, cv::Point(x, y + label_size.height),
                cv::FONT_HERSHEY_SIMPLEX, 1.0, cv::Scalar(0, 0, 0));

    return 0;
}

static int draw_fps(cv::Mat& rgb)
{
    // resolve moving average
    float avg_fps = 0.f;
    {
        static double t0 = 0.f;
        static float fps_history[10] = {0.f};

        double t1 = ncnn::get_current_time();
        if (t0 == 0.f)
        {
            t0 = t1;
            return 0;
        }

        float fps = 1000.f / (t1 - t0);
        t0 = t1;

        for (int i = 9; i >= 1; i--)
        {
            fps_history[i] = fps_history[i - 1];
        }
        fps_history[0] = fps;

        if (fps_history[9] == 0.f)
        {
            return 0;
        }

        for (int i = 0; i < 10; i++)
        {
            avg_fps += fps_history[i];
        }
        avg_fps /= 10.f;
    }

    char text[32];
    sprintf(text, "FPS=%.2f", avg_fps);

    int baseLine = 0;
    cv::Size label_size = cv::getTextSize(text, cv::FONT_HERSHEY_SIMPLEX, 0.5, 1, &baseLine);

    int y = 0;
    int x = rgb.cols - label_size.width;

    cv::rectangle(rgb, cv::Rect(cv::Point(x, y), cv::Size(label_size.width, label_size.height + baseLine)),
                    cv::Scalar(255, 255, 255), -1);

    cv::putText(rgb, text, cv::Point(x, y + label_size.height),
                cv::FONT_HERSHEY_SIMPLEX, 0.5, cv::Scalar(0, 0, 0));

    return 0;
}

static PPOCRv5* g_ppocrv5 = 0;
static ncnn::Mutex lock;

class MyNdkCamera : public NdkCameraWindow
{
public:
    virtual void on_image_render(cv::Mat& rgb) const;
};

void MyNdkCamera::on_image_render(cv::Mat& rgb) const
{
    // ppocrv5
    {
        ncnn::MutexLockGuard g(lock);

        if (g_ppocrv5)
        {
            if (is_photo_mode) 
            {
                // Check if capture is requested
                ncnn::MutexLockGuard cg(capture_lock);
                if (capture_requested)
                {
                    // Use full_capture_rgb if available (full sensor frame, pre-ROI-crop)
                    cv::Mat full_frame = full_capture_rgb.empty() ? rgb.clone() : full_capture_rgb.clone();
                    __android_log_print(ANDROID_LOG_DEBUG, "ncnn", "[PhotoMode] capture_requested=true, full_frame=%dx%d, rgb=%dx%d, target_norm_w=%.3f, target_norm_h=%.3f", 
                                        full_frame.cols, full_frame.rows, rgb.cols, rgb.rows, target_norm_w, target_norm_h);
                    
                    // 1. Save original full sensor frame
                    cv::Mat bgr_orig;
                    cv::cvtColor(full_frame, bgr_orig, cv::COLOR_RGB2BGR);
                    cv::imwrite(capture_save_path, bgr_orig);
                    __android_log_print(ANDROID_LOG_DEBUG, "ncnn", "[PhotoMode] original saved to %s (%dx%d)", capture_save_path.c_str(), bgr_orig.cols, bgr_orig.rows);

                    std::string cropped_path = "";

                    // 2. Crop from rgb (matches preview/overlay) for OCR
                    if (target_norm_w > 0.0f && target_norm_h > 0.0f) 
                    {
                        // Crop relative to rgb (the preview frame, matches overlay)
                        int crop_w = (int)(rgb.cols * target_norm_w);
                        int crop_h = (int)(rgb.rows * target_norm_h);
                        __android_log_print(ANDROID_LOG_DEBUG, "ncnn", "[PhotoMode] crop_w=%d, crop_h=%d from rgb %dx%d", crop_w, crop_h, rgb.cols, rgb.rows);
                        
                        if (crop_w > 0 && crop_w <= rgb.cols && crop_h > 0 && crop_h <= rgb.rows) 
                        {
                            int crop_x = (rgb.cols - crop_w) / 2;
                            int crop_y = (rgb.rows - crop_h) / 2;
                            cv::Rect crop_region(crop_x, crop_y, crop_w, crop_h);
                            cv::Mat crop_rgb = rgb(crop_region).clone();
                            __android_log_print(ANDROID_LOG_DEBUG, "ncnn", "[PhotoMode] cropped region: x=%d y=%d w=%d h=%d", crop_x, crop_y, crop_w, crop_h);

                            // 3. Run OCR on the cropped region
                            std::vector<Object> objects;
                            g_ppocrv5->detect_and_recognize(crop_rgb, objects);
                            __android_log_print(ANDROID_LOG_DEBUG, "ncnn", "[PhotoMode] OCR found %d objects", (int)objects.size());

                            // 4. Extract text
                            std::string all_text;
                            for (size_t i = 0; i < objects.size(); i++)
                            {
                                std::string line_text;
                                for (size_t j = 0; j < objects[i].text.size(); j++)
                                {
                                    const Character& ch = objects[i].text[j];
                                    if (ch.id >= 0 && ch.id < character_dict_size)
                                    {
                                        line_text += character_dict[ch.id];
                                    }
                                }
                                if (!line_text.empty())
                                {
                                    if (!all_text.empty()) all_text += "\n";
                                    all_text += line_text;
                                }
                            }
                            const_cast<MyNdkCamera*>(this)->set_ocr_text(all_text);
                            __android_log_print(ANDROID_LOG_DEBUG, "ncnn", "[PhotoMode] OCR text length=%d", (int)all_text.length());

                            // 5. Offset bbox: crop_in_rgb → rgb → full_frame
                            // ROI offset: rgb is centered in full_frame
                            int roi_offset_x = (full_frame.cols - rgb.cols) / 2;
                            int roi_offset_y = (full_frame.rows - rgb.rows) / 2;
                            for (size_t i = 0; i < objects.size(); i++)
                            {
                                objects[i].rrect.center.x += crop_x + roi_offset_x;
                                objects[i].rrect.center.y += crop_y + roi_offset_y;
                            }

                            // 6. Draw bounding boxes + text labels on the FULL sensor frame
                            g_ppocrv5->draw(full_frame, objects);

                            // 7. Save the full frame with bounding boxes
                            cv::Mat bgr_full;
                            cv::cvtColor(full_frame, bgr_full, cv::COLOR_RGB2BGR);
                            
                            size_t dot_pos = capture_save_path.find_last_of('.');
                            if (dot_pos != std::string::npos) {
                                cropped_path = capture_save_path.substr(0, dot_pos) + "_crop" + capture_save_path.substr(dot_pos);
                            } else {
                                cropped_path = capture_save_path + "_crop.jpg";
                            }
                            cv::imwrite(cropped_path, bgr_full);
                            __android_log_print(ANDROID_LOG_DEBUG, "ncnn", "[PhotoMode] full frame with bbox saved to %s (%dx%d)", cropped_path.c_str(), bgr_full.cols, bgr_full.rows);
                        }
                        else
                        {
                            __android_log_print(ANDROID_LOG_WARN, "ncnn", "[PhotoMode] crop dimensions invalid! crop_w=%d crop_h=%d vs full=%dx%d", crop_w, crop_h, full_frame.cols, full_frame.rows);
                        }
                    }
                    else
                    {
                        __android_log_print(ANDROID_LOG_WARN, "ncnn", "[PhotoMode] target_norm not set! w=%.3f h=%.3f", target_norm_w, target_norm_h);
                    }

                    if (!cropped_path.empty()) {
                        captured_photo_path = capture_save_path + "|" + cropped_path;
                    } else {
                        captured_photo_path = capture_save_path;
                    }
                    
                    // Clear the full capture frame
                    const_cast<MyNdkCamera*>(this)->full_capture_rgb = cv::Mat();
                    capture_requested = false;
                    __android_log_print(ANDROID_LOG_DEBUG, "ncnn", "[PhotoMode] captured_photo_path=%s", captured_photo_path.c_str());
                }
                else
                {
                    // Preview mode: detect-only (no recognition) to show bounding boxes
                    std::vector<Object> objects;
                    g_ppocrv5->detect(rgb, objects);

                    // Draw bounding boxes only (no text labels since no recognition)
                    static const cv::Scalar bbox_color(80, 175, 76); // green
                    for (size_t i = 0; i < objects.size(); i++)
                    {
                        cv::Point2f corners[4];
                        objects[i].rrect.points(corners);
                        cv::line(rgb, corners[0], corners[1], bbox_color, 2);
                        cv::line(rgb, corners[1], corners[2], bbox_color, 2);
                        cv::line(rgb, corners[2], corners[3], bbox_color, 2);
                        cv::line(rgb, corners[3], corners[0], bbox_color, 2);
                    }
                }
            }
            else 
            {
                // Realtime Mode
                std::vector<Object> objects;
                g_ppocrv5->detect_and_recognize(rgb, objects);

                // extract OCR text from recognized objects
                std::string all_text;
                for (size_t i = 0; i < objects.size(); i++)
                {
                    std::string line_text;
                    for (size_t j = 0; j < objects[i].text.size(); j++)
                    {
                        const Character& ch = objects[i].text[j];
                        if (ch.id >= 0 && ch.id < character_dict_size)
                        {
                            line_text += character_dict[ch.id];
                        }
                    }
                    if (!line_text.empty())
                    {
                        if (!all_text.empty())
                            all_text += "\n";
                        all_text += line_text;
                    }
                }

                // store OCR text (thread-safe)
                const_cast<MyNdkCamera*>(this)->set_ocr_text(all_text);

                // handle photo capture request in realtime mode
                {
                    ncnn::MutexLockGuard cg(capture_lock);
                    if (capture_requested)
                    {
                        // save the frame with OCR overlay drawn on it
                        g_ppocrv5->draw(rgb, objects);

                        cv::Mat final_rgb = rgb;
                        if (target_norm_w > 0.0f && target_norm_h > 0.0f) 
                        {
                            int crop_w = (int)(rgb.cols * target_norm_w);
                            int crop_h = (int)(rgb.rows * target_norm_h);
                            if (crop_w > 0 && crop_w <= rgb.cols && crop_h > 0 && crop_h <= rgb.rows) 
                            {
                                int crop_x = (rgb.cols - crop_w) / 2;
                                int crop_y = (rgb.rows - crop_h) / 2;
                                cv::Rect crop_region(crop_x, crop_y, crop_w, crop_h);
                                final_rgb = rgb(crop_region).clone();
                            }
                        }

                        cv::Mat bgr;
                        cv::cvtColor(final_rgb, bgr, cv::COLOR_RGB2BGR);
                        cv::imwrite(capture_save_path, bgr);

                        captured_photo_path = capture_save_path;
                        capture_requested = false;
                        __android_log_print(ANDROID_LOG_DEBUG, "ncnn", "photo saved to %s", captured_photo_path.c_str());

#ifndef NDEBUG
                        draw_fps(rgb);
#endif
                        return; // already drew overlay, skip drawing again
                    }
                }

                g_ppocrv5->draw(rgb, objects);
            }
        }
        else
        {
            draw_unsupported(rgb);
        }
    }

#ifndef NDEBUG
    draw_fps(rgb);
#endif
}

static MyNdkCamera* g_camera = 0;

extern "C" {

JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved)
{
    __android_log_print(ANDROID_LOG_DEBUG, "ncnn", "JNI_OnLoad");

    g_camera = new MyNdkCamera;

    ncnn::create_gpu_instance();

    return JNI_VERSION_1_4;
}

JNIEXPORT void JNI_OnUnload(JavaVM* vm, void* reserved)
{
    __android_log_print(ANDROID_LOG_DEBUG, "ncnn", "JNI_OnUnload");

    {
        ncnn::MutexLockGuard g(lock);

        delete g_ppocrv5;
        g_ppocrv5 = 0;
    }

    ncnn::destroy_gpu_instance();

    delete g_camera;
    g_camera = 0;
}

// public native boolean loadModel(String detParam, String detModel, String recParam, String recModel, int sizeid, int cpugpu);
JNIEXPORT jboolean JNICALL Java_com_iweka_ocr_PPOCRv5Ncnn_loadModel(JNIEnv* env, jobject thiz, jstring detParam, jstring detModel, jstring recParam, jstring recModel, jint sizeid, jint cpugpu)
{
    if (sizeid < 0 || sizeid > 4 || cpugpu < 0 || cpugpu > 2)
    {
        return JNI_FALSE;
    }

    const char* det_parampath = env->GetStringUTFChars(detParam, nullptr);
    const char* det_modelpath = env->GetStringUTFChars(detModel, nullptr);
    const char* rec_parampath = env->GetStringUTFChars(recParam, nullptr);
    const char* rec_modelpath = env->GetStringUTFChars(recModel, nullptr);

    __android_log_print(ANDROID_LOG_DEBUG, "ncnn", "loadModel from files: %s", det_parampath);

    const int sizetypes[5] =
    {
        320,
        400,
        480,
        560,
        640
    };

    // Determine fp16 usage based on model type (heuristic: if path contains "server", disable fp16)
    std::string det_param_str(det_parampath);
    bool use_fp16 = (det_param_str.find("server") == std::string::npos);
    bool use_gpu = (int)cpugpu == 1;
    bool use_turnip = (int)cpugpu == 2;

    // reload
    {
        ncnn::MutexLockGuard g(lock);

        delete g_ppocrv5;
        g_ppocrv5 = 0;

        ncnn::destroy_gpu_instance();

        if (use_turnip)
        {
            ncnn::create_gpu_instance("libvulkan_freedreno.so");
        }
        else if (use_gpu)
        {
            ncnn::create_gpu_instance();
        }

        g_ppocrv5 = new PPOCRv5;
        g_ppocrv5->load(det_parampath, det_modelpath, rec_parampath, rec_modelpath, use_fp16, use_gpu || use_turnip);
        g_ppocrv5->set_target_size(sizetypes[(int)sizeid]);
    }

    env->ReleaseStringUTFChars(detParam, det_parampath);
    env->ReleaseStringUTFChars(detModel, det_modelpath);
    env->ReleaseStringUTFChars(recParam, rec_parampath);
    env->ReleaseStringUTFChars(recModel, rec_modelpath);

    return JNI_TRUE;
}

// public native boolean openCamera(int facing);
JNIEXPORT jboolean JNICALL Java_com_iweka_ocr_PPOCRv5Ncnn_openCamera(JNIEnv* env, jobject thiz, jint facing)
{
    if (facing < 0 || facing > 1)
        return JNI_FALSE;

    __android_log_print(ANDROID_LOG_DEBUG, "ncnn", "openCamera %d", facing);

    g_camera->open((int)facing);

    return JNI_TRUE;
}

// public native boolean closeCamera();
JNIEXPORT jboolean JNICALL Java_com_iweka_ocr_PPOCRv5Ncnn_closeCamera(JNIEnv* env, jobject thiz)
{
    __android_log_print(ANDROID_LOG_DEBUG, "ncnn", "closeCamera");

    g_camera->close();

    return JNI_TRUE;
}

// public native boolean setOutputWindow(Surface surface);
JNIEXPORT jboolean JNICALL Java_com_iweka_ocr_PPOCRv5Ncnn_setOutputWindow(JNIEnv* env, jobject thiz, jobject surface)
{
    ANativeWindow* win = ANativeWindow_fromSurface(env, surface);

    __android_log_print(ANDROID_LOG_DEBUG, "ncnn", "setOutputWindow %p", win);

    g_camera->set_window(win);

    return JNI_TRUE;
}

// public native boolean clearOutputWindow();
JNIEXPORT jboolean JNICALL Java_com_iweka_ocr_PPOCRv5Ncnn_clearOutputWindow(JNIEnv* env, jobject thiz)
{
    __android_log_print(ANDROID_LOG_DEBUG, "ncnn", "clearOutputWindow");

    if (g_camera)
    {
        g_camera->clear_window();
    }

    return JNI_TRUE;
}

// public native boolean toggleFlash();
JNIEXPORT jboolean JNICALL Java_com_iweka_ocr_PPOCRv5Ncnn_toggleFlash(JNIEnv* env, jobject thiz)
{
    if (!g_camera)
        return JNI_FALSE;

    int ret = g_camera->toggle_flash();
    return ret == 0 ? JNI_TRUE : JNI_FALSE;
}

// public native String takePhoto(String savePath);
JNIEXPORT jstring JNICALL Java_com_iweka_ocr_PPOCRv5Ncnn_takePhoto(JNIEnv* env, jobject thiz, jstring savePath)
{
    if (!g_camera)
        return env->NewStringUTF("");

    const char* save_path = env->GetStringUTFChars(savePath, nullptr);
    g_camera->request_capture(save_path);
    env->ReleaseStringUTFChars(savePath, save_path);

    // wait for capture to complete (up to 2 seconds)
    std::string photo_path;
    for (int i = 0; i < 40; i++)
    {
        ncnn::sleep(50); // 50ms
        photo_path = g_camera->get_captured_photo_path();
        if (!photo_path.empty())
            break;
    }

    return env->NewStringUTF(photo_path.c_str());
}

// public native String getOcrText();
JNIEXPORT jstring JNICALL Java_com_iweka_ocr_PPOCRv5Ncnn_getOcrText(JNIEnv* env, jobject thiz)
{
    if (!g_camera)
        return env->NewStringUTF("");

    std::string text = g_camera->get_ocr_text();
    return env->NewStringUTF(text.c_str());
}

// public native boolean setTargetRect(float norm_w, float norm_h);
JNIEXPORT jboolean JNICALL Java_com_iweka_ocr_PPOCRv5Ncnn_setTargetRect(JNIEnv* env, jobject thiz, jfloat norm_w, jfloat norm_h)
{
    if (g_camera)
    {
        g_camera->set_target_rect(norm_w, norm_h);
        return JNI_TRUE;
    }
    return JNI_FALSE;
}

// public native boolean setPhotoMode(boolean isPhoto);
JNIEXPORT jboolean JNICALL Java_com_iweka_ocr_PPOCRv5Ncnn_setPhotoMode(JNIEnv* env, jobject thiz, jboolean isPhoto)
{
    if (g_camera)
    {
        g_camera->set_photo_mode(isPhoto == JNI_TRUE);
        return JNI_TRUE;
    }
    return JNI_FALSE;
}

// public native String ocrFromImage(String imagePath);
JNIEXPORT jstring JNICALL Java_com_iweka_ocr_PPOCRv5Ncnn_ocrFromImage(JNIEnv* env, jobject thiz, jstring imagePath)
{
    const char* image_path = env->GetStringUTFChars(imagePath, nullptr);
    std::string image_path_str(image_path);

    __android_log_print(ANDROID_LOG_DEBUG, "ncnn", "ocrFromImage: %s", image_path);

    cv::Mat bgr = cv::imread(image_path);
    env->ReleaseStringUTFChars(imagePath, image_path);

    if (bgr.empty())
    {
        __android_log_print(ANDROID_LOG_ERROR, "ncnn", "ocrFromImage: failed to load image");
        return env->NewStringUTF("");
    }

    cv::Mat rgb;
    cv::cvtColor(bgr, rgb, cv::COLOR_BGR2RGB);

    ncnn::MutexLockGuard g(lock);

    if (!g_ppocrv5)
    {
        __android_log_print(ANDROID_LOG_ERROR, "ncnn", "ocrFromImage: model not loaded");
        return env->NewStringUTF("");
    }

    std::vector<Object> objects;
    g_ppocrv5->detect_and_recognize(rgb, objects);

    // extract OCR text (same logic as on_image_render)
    std::string all_text;
    for (size_t i = 0; i < objects.size(); i++)
    {
        std::string line_text;
        for (size_t j = 0; j < objects[i].text.size(); j++)
        {
            const Character& ch = objects[i].text[j];
            if (ch.id >= 0 && ch.id < character_dict_size)
            {
                line_text += character_dict[ch.id];
            }
        }
        if (!line_text.empty())
        {
            if (!all_text.empty())
                all_text += "\n";
            all_text += line_text;
        }
    }

    __android_log_print(ANDROID_LOG_DEBUG, "ncnn", "ocrFromImage: found %d objects, text length %d",
                        (int)objects.size(), (int)all_text.length());

    // Draw bounding boxes + text labels on the image (same as realtime)
    std::string bbox_path;
    if (!objects.empty())
    {
        g_ppocrv5->draw(rgb, objects);

        // Save annotated image as separate _bbox file (don't overwrite original)
        size_t dot_pos = image_path_str.find_last_of('.');
        if (dot_pos != std::string::npos)
        {
            bbox_path = image_path_str.substr(0, dot_pos) + "_bbox" + image_path_str.substr(dot_pos);
        }
        else
        {
            bbox_path = image_path_str + "_bbox.jpg";
        }

        cv::Mat bgr_out;
        cv::cvtColor(rgb, bgr_out, cv::COLOR_RGB2BGR);
        cv::imwrite(bbox_path, bgr_out);

        __android_log_print(ANDROID_LOG_DEBUG, "ncnn", "ocrFromImage: bbox saved to %s", bbox_path.c_str());
    }

    return env->NewStringUTF(all_text.c_str());
}

}

