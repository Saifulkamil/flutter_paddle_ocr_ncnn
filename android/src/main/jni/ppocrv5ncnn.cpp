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

            // handle photo capture request
            {
                ncnn::MutexLockGuard cg(capture_lock);
                if (capture_requested)
                {
                    // save the frame with OCR overlay drawn on it
                    g_ppocrv5->draw(rgb, objects);

                    // convert RGB to BGR for imwrite
                    cv::Mat bgr;
                    cv::cvtColor(rgb, bgr, cv::COLOR_RGB2BGR);
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

}
