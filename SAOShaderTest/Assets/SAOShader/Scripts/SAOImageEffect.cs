/**
 * SAO処理時のImage Effectクラス.

 The MIT License

Copyright © 2017 ft-lab

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

 */
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

[RequireComponent(typeof(Camera))]
[ExecuteInEditMode()]       // Editor上でもエフェクトを反映する.
#if UNITY_5_4_OR_NEWER
    //[ImageEffectAllowedInSceneView]     // Scene上でエフェクトを反映.
#endif
public class SAOImageEffect : MonoBehaviour {
    public enum DRAW_MODE {
        drawDefault,        // 何もしない.
        drawAO,              // AOを反映.
        drawAOOnly          // AOのみを反映.
    };

    // 調整用パラメータ.
    [SerializeField] private DRAW_MODE m_drawMode = DRAW_MODE.drawAO;

    [SerializeField] [Range(0, 1)] private float m_bias = 0.5f;
    [SerializeField] [Range(0.0f, 1.0f)] private float m_intensity = 0.005f;
    [SerializeField] [Range(0, 10)] private float m_scale = 2.0f;
    [SerializeField] [Range(1, 100)] private float m_kernelRadius = 40.0f;
    [SerializeField] [Range(0, 1)] private float m_minResolution = 0.0f;
    [SerializeField] private float m_falloffDistance = 500.0f;
    [SerializeField] private bool m_blur = true;
    [SerializeField] [Range(0.5f, 150)] private float m_blurStdDev = 4.0f;
    [SerializeField] [Range(0.0f, 0.1f)] private float m_blurDepthCutoff = 0.01f;

    // privateパラメータ.
    private Shader m_saoShader = null;              // sao用のShader.
    private Shader m_saoCopyShader = null;          // コピーするだけのShader.
    private Shader m_saoDepthLimitedBlurShader = null;  // BlurをかけるShader.
    private Shader m_saoBlendShader = null;             // レンダリング結果とAOを合成するShader.
    
    private Material m_saoMaterial = null;     // SAO計算用のマテリアル.
    private Material m_copyMaterial = null;    // 単純にコピーするだけのマテリアル.
    private Material m_vBlurMaterial = null;   // 垂直ブラーのマテリアル.
    private Material m_hBlurMaterial = null;   // 水平ブラーのマテリアル.
    private Material m_blendMaterial = null;   // AOとレンダリング結果を合成するマテリアル.

    private RenderTexture m_texAO;
    private RenderTexture m_texBlur;

    /**
     * カメラがシーンをカリングする前に呼ばれる.
     */
    void OnPreCull () {
        // depth + normalの取得を有効化.
        Camera cam = GetComponent<Camera>();
        cam.depthTextureMode = DepthTextureMode.DepthNormals;
    }

    /**
     * 有効化時.
     */
    void OnEnable () {
        CreateMaterial();       // マテリアルの確保.
    }

    /**
     * 無効化時.
     */
    void OnDisable () {
        DestroyMaterial();       // マテリアルの解放.
    }

    /**
     * マテリアルの割り当て.
     */
    void CreateMaterial () {
        // Shaderの読み込み.
        m_saoShader                 = Resources.Load("Shaders/sao", typeof(Shader)) as Shader;
        m_saoCopyShader             = Resources.Load("Shaders/sao_copy", typeof(Shader)) as Shader;
        m_saoDepthLimitedBlurShader = Resources.Load("Shaders/sao_depthLimitedBlur", typeof(Shader)) as Shader;
        m_saoBlendShader            = Resources.Load("Shaders/sao_blend", typeof(Shader)) as Shader;
        if (m_saoShader == null || m_saoCopyShader == null || m_saoDepthLimitedBlurShader == null || m_saoBlendShader == null) return;

        // SAO処理のマテリアル.
        m_saoMaterial = new Material(m_saoShader);

        // 色情報をコピーするだけのShader.
        m_copyMaterial = new Material(m_saoCopyShader);

        // ブラー用のマテリアルを生成.
        m_vBlurMaterial = new Material(m_saoDepthLimitedBlurShader);
        m_hBlurMaterial = new Material(m_saoDepthLimitedBlurShader);

        // AOとレンダリング結果を合成するマテリアルを生成.
        m_blendMaterial = new Material(m_saoBlendShader);
    }

    /**
     * マテリアルの破棄.
     */
    void DestroyMaterial () {
        if (m_saoShader != null) Resources.UnloadAsset(m_saoShader);
        if (m_saoCopyShader != null) Resources.UnloadAsset(m_saoCopyShader);
        if (m_saoDepthLimitedBlurShader != null) Resources.UnloadAsset(m_saoDepthLimitedBlurShader);
        if (m_saoBlendShader != null) Resources.UnloadAsset(m_saoBlendShader);

        if (m_saoMaterial != null) DestroyImmediate(m_saoMaterial);
        if (m_copyMaterial != null) DestroyImmediate(m_copyMaterial);
        if (m_vBlurMaterial != null) DestroyImmediate(m_vBlurMaterial);
        if (m_hBlurMaterial != null) DestroyImmediate(m_hBlurMaterial);
        if (m_blendMaterial != null) DestroyImmediate(m_blendMaterial);
    }

    /**
     * レンダリング処理.
     */
    void OnRenderImage (RenderTexture source, RenderTexture destination) {
        if (m_saoMaterial == null || m_copyMaterial == null || m_vBlurMaterial == null || m_hBlurMaterial == null) {
            Graphics.Blit(source, destination);
            return;
        }

        // 何もしない場合はそのまま返す.
        if (m_drawMode == DRAW_MODE.drawDefault) {
            Graphics.Blit(source, destination, m_copyMaterial);
            return;            
        }

        // 作業用のバッファを確保.
        m_texAO = RenderTexture.GetTemporary(source.width, source.height);
        m_texBlur = RenderTexture.GetTemporary(source.width, source.height);

        // MaterialパラメータをShaderに渡す.
        UpdateSAOMaterial(source.width, source.height);

        // AO計算のShaderを実行.
        Graphics.Blit(source, m_texAO, m_saoMaterial);     // ここで、m_saoMaterialで割り当てられたマテリアルにより、Shaderが実行される.

        // ブラーをかける.
        if (m_blur) {
            UpdateBlurMaterial(source.width, source.height);
            Graphics.Blit(m_texAO, m_texBlur, m_vBlurMaterial);
            Graphics.Blit(m_texBlur, m_texAO, m_hBlurMaterial);
        }

        if (m_drawMode == DRAW_MODE.drawAOOnly) {
            // AOの色情報をコピー.
            Graphics.Blit(m_texAO, destination, m_copyMaterial);

        } else {
            // レンダリング結果にAOを合成.
            m_blendMaterial.SetTexture("_AOTex", m_texAO);
            m_blendMaterial.SetFloat("_Intensity", 1.0f);
            Graphics.Blit(source, destination, m_blendMaterial);
        }

        // 作業用バッファを解放.
        RenderTexture.ReleaseTemporary(m_texAO);
        RenderTexture.ReleaseTemporary(m_texBlur);
    }

    /**
     * AO用のマテリアルのパラメータをShaderに渡す.
     */    
    private void UpdateSAOMaterial (float width, float height) {
        m_saoMaterial.SetFloat("_Bias", m_bias);        
        m_saoMaterial.SetFloat("_Intensity", m_intensity);        
        m_saoMaterial.SetFloat("_Scale", m_scale);        
        m_saoMaterial.SetFloat("_KernelRadius", m_kernelRadius);        
        m_saoMaterial.SetFloat("_MinResolution", m_minResolution);
        m_saoMaterial.SetFloat("_FalloffDistance", m_falloffDistance);
        m_saoMaterial.SetInt("_Blur", m_blur ? 1 : 0);        
        m_saoMaterial.SetFloat("_BlurStdDev", m_blurStdDev);        
        m_saoMaterial.SetFloat("_BlurDepthCutoff", m_blurDepthCutoff);
        m_saoMaterial.SetVector("_Size", new Vector4(width, height, 0, 0));
    }

    /**
     * ブラー用のウエイト値を取得 (Gaussian).
     */
    private List<float> CreateSampleWeights (int kernelRadius, float stdDev) {
        List<float> weights = new List<float>();
        for (int i = 0; i <= kernelRadius; i++) {
            weights.Add(Mathf.Exp(-(float)(i * i) / (2.0f * (stdDev * stdDev))) / (Mathf.Sqrt(2.0f * Mathf.PI) * stdDev));
        }
        return weights;
    }

    /**
     * ブラー用のサンプル値情報を取得.
     */
    private List<Vector4> CreateSampleOffsets (int kernelRadius, Vector2 uvIncrement) {
        List<Vector4> offsets = new List<Vector4>();
        for (int i = 0; i <= kernelRadius; i++) {
            offsets.Add(new Vector4(uvIncrement.x * i, uvIncrement.y * i, 0, 0));
        }
        return offsets;
    }

    /**
     * ブラー用の初期指定.
     */
    private void BlurConfigure (Material material, int kernelRadius, float stdDev, Vector2 uvIncrement) {
        List<float> weights = CreateSampleWeights(kernelRadius, stdDev);
        List<Vector4> offsets = CreateSampleOffsets(kernelRadius, uvIncrement);

        material.SetFloatArray("_SampleWeights", weights);
        material.SetVectorArray("_SampleUVOffsets", offsets);
    }

    /**
     * ブラー用のマテリアルのパラメータをShaderに渡す.
     */
    private void UpdateBlurMaterial (float width, float height) {
        int blurRadiusI = 4;        // これは固定.

        m_vBlurMaterial.SetVector("_Size", new Vector4(width, height, 0, 0));
        m_vBlurMaterial.SetFloat("_BlurDepthCutoff", m_blurDepthCutoff);
        BlurConfigure(m_vBlurMaterial, blurRadiusI, m_blurStdDev, new Vector2(0, 1));

        m_hBlurMaterial.SetVector("_Size", new Vector4(width, height, 0, 0));
        m_hBlurMaterial.SetFloat("_BlurDepthCutoff", m_blurDepthCutoff);
        BlurConfigure(m_hBlurMaterial, blurRadiusI, m_blurStdDev, new Vector2(1, 0));
    }
}
