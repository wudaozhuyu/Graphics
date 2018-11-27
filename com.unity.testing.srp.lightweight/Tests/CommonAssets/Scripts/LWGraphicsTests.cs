using System.Collections;
using System.Linq;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;
using UnityEngine.TestTools.Graphics;
using UnityEngine.SceneManagement;

public class LWGraphicsTests
{

    public const string lwPackagePath = "Packages/com.unity.testing.srp.lightweight/Tests/ReferenceImages";

    [UnityTest, Category("LightWeightRP")]
    [PrebuildSetup("SetupGraphicsTestCases")]
    [UseGraphicsTestCases(lwPackagePath)]
    public IEnumerator Run(GraphicsTestCase testCase)
    {
        SceneManager.LoadScene(testCase.ScenePath);

        // Always wait one frame for scene load
        yield return null;

        var cameras = GameObject.FindGameObjectsWithTag("MainCamera").Select(x=>x.GetComponent<Camera>());
        var settings = Object.FindObjectOfType<LWGraphicsTestSettings>();
        Assert.IsNotNull(settings, "Invalid test scene, couldn't find LWGraphicsTestSettings");

        Scene scene = SceneManager.GetActiveScene();

        if (scene.name.Substring(3, 4).Equals("_xr_"))
        {
            UnityEngine.XR.XRSettings.LoadDeviceByName("MockHMD");
            yield return null;

            UnityEngine.XR.XRSettings.enabled = true;
            yield return null;

            foreach (var camera in cameras)
                camera.stereoTargetEye = StereoTargetEyeMask.Both;
        }

        for (int i = 0; i < settings.WaitFrames; i++)
            yield return null;

        ImageAssert.AreEqual(testCase.ReferenceImage, cameras.Where(x=>x != null), settings.ImageComparisonSettings);
    }

#if UNITY_EDITOR
    [TearDown]
    public void DumpImagesInEditor()
    {
        UnityEditor.TestTools.Graphics.ResultsUtility.ExtractImagesFromTestProperties(TestContext.CurrentContext.Test);
    }
#endif
}
