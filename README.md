## *Model of parafoveal chromatic and luminance temporal contrast sensitivity of humans and monkeys*
This repository contains data and analysis code from Gelfand, E. C., & Horwitz, G. D. (2018). Model of parafoveal chromatic and luminance temporal contrast sensitivity of humans and monkeys. *Journal of Vision*, 18(12), 1-1; DOI: [10.1167/18.12.1](http://dx.doi.org/10.1167/18.12.1).

The data are contained in two MATLAB .mat files. `LMTF_data_A_public.mat` contains data from monkey 1 and `LMTF_data_U_public.mat` contains data from monkey 2. Each file contains a single n x 7 matrix called `data`.

Each row of `data` represents a single threshold estimate. The columns are as follows:

* L-cone contrast at detection threshold
* M-cone contrast at detection threshold
* Temporal frequency (Hz) at detection threshold
* Threshold out of gamut (1 = yes, 0 = no). If 1, then the L- and M-cone contrasts in columns 1 and 2 are at the gamut edge and should not be taken as reasonable estimates of threshold. 
* Horizontal position of the stimulus in the visual field (in tenths of degrees)
* Vertical position of the stimulus in the visual field (in tenths of degrees)
* Session identifier. Four threshold measurements were typically made in each session.

The analysis code is `LMTF_generate_module_data_public.m`. To execute this code, load one of the two datasets into the workspace and then run `LMTF_generate_module_data_public(data)`.

The output of `LMTF_generate_module_data_public` is a structure with four fields.

* `legacy` This is a structure with 26 fields, three of which are more important than the other 23. These fields are:
  * `legacy.mode5params` An 18-element vector containing the fitted parameter values of the model described in the paper. See `tf_fitterr3.m` for more information. The 18 parameters (with reference to the equations in the paper) are as follows.
    * ζ<sub>1</sub>: The transience of the non-opponent detection mechanism (Eq. 6)
    * n<sub>1</sub>: The number of low-pass stages for the first filter of the non-opponent detection mechanism (Eq. 5)
    * n<sub>2</sub>: The difference in the number of low-pass stages between the first and second filters that compose the non-opponent detection mechanism (Eq. 5)    
    * τ<sub>1</sub>: The log10 time constant (in s) of the first filter of the non-opponent detection mechanism (Eq. 5)
    * τ<sub>2</sub>: The difference in log10 time constant between the first and second filters that compose the non-opponent detection mechanism (Eq. 5)
    * ζ<sub>1</sub>: The transience of the opponent detection mechanism (Eq. 6)
    * n<sub>1</sub>: The number of low-pass stages for the first filter of the opponent detection mechanism (Eq. 5)
    * n<sub>2</sub>: The difference in the number of low-pass stages between the first and second filters that compose the opponent detection mechanism (Eq. 5)
    * τ<sub>1</sub>: The log10 time constant (in s) of the first filter of the opponent detection mechanism (Eq. 5)
    * τ<sub>2</sub>: The difference in log10 time constant between the first and second filters that compose the opponent detection mechanism (Eq. 5)
    * θ: The angle (in radians) of the non-opponent detection mechanism in the LM plane.
    * b<sub>0, LUM</sub>: The gain of the non-opponent detection mechanism at the fovea (Eq. 10).
    * b<sub>1, LUM</sub>: The slope of the fall-off in sensitivity of the non-opponent detection mechanism with eccentricity (Eq. 10)
    * b<sub>2</sub>: Sensitivity anisotropy between horizontal and vertical meridians, identical for the non-opponent and the opponent mechanisms (Eq. 10).
    * b<sub>3, LUM</sub>: Upper/lower visual field asymmetry for the non-opponent detection mechanism (Eq. 10).
    * b<sub>0, RG</sub>: The gain of the opponent detection mechanism at the fovea (Eq. 10).
    * b<sub>1, RG</sub>: The slope of the fall-off in sensitivity of the opponent detection mechanism with eccentricity (Eq. 10).
    * b<sub>3</sub>, <sub>RG</sub>: Upper/lower visual field asymmetry for the opponent detection mechanism (Eq. 10).

  * `legacy.mode5models` A 13 x m matrix of parameter values describing the model fits at each of the m visual field locations tested. See `tf_fitterr2.m` for more information. Parameters 1–6 control the non-opponent (LUM) detection mechanism. Parameters 7–12 control the opponent (RG) detection mechanism.
    * ξ<sub>1, LUM</sub>: The gain of the non-opponent detection mechanism (Eq. 6)
    * ζ<sub>1, LUM</sub>: The transience of the non-opponent detection mechanism (Eq. 6)
    * n<sub>1, LUM</sub>: The number of low-pass stages for the first filter of the non-opponent detection mechanism (Eq. 5)
    * n<sub>2, LUM</sub>: The difference in the number of low-pass stages between the first and second filters that compose the non-opponent detection mechanism (Eq. 5)
    * τ<sub>1, LUM</sub>: The log10 time constant (in s) of the first filter of the non-opponent detection mechanism (Eq. 5)
    * τ<sub>2, LUM</sub>: The difference in log10 time constant between the first and second filters that compose the non-opponent detection mechanism (Eq. 5)
    * ξ<sub>1, RG</sub>: The gain of the opponent detection mechanism (Eq. 6)
    * ζ<sub>1, RG</sub>: The transience of the opponent detection mechanism (Eq. 6)
    * n<sub>1, RG</sub>: The number of low-pass stages for the first filter of the opponent detection mechanism (Eq. 5)
    * n<sub>2, RG</sub>: The difference in the number of low-pass stages between the first and second filters that compose the opponent detection mechanism (Eq. 5)
    * τ<sub>1, RG</sub>: The log10 time constant (in s) of the first filter of the opponent detection mechanism (Eq. 5)
    * τ<sub>2, RG</sub>: The difference in log10 time constant between the first and second filters that compose the opponent detection mechanism (Eq. 5)
    * θ: The angle (in radians) of the non-opponent detection mechanism in the LM plane.
  * `legacy.mode5fvs` An m element vector containing the error of the model fit at each of the m locations tested. The other fields in data.legacy are similar but are based on models that were rejected but used in the fitting process.
* `raw` Contains the raw data organized by location in the visual field.
* `eccs` An m x 2 matrix providing a list of the visual field locations tested (in 10th of degree of visual angle). 
* `domain` Unused.

To inspect the model fits and explore the action of the parameters values on the function fits, use `LMTFBrowser.m`, passing the structure produced by `LMTF_generate_module_data_public.m` in as the input argument to the function. `LMTFBrowser.m` is essentially completely undocumented, but on the off chance that any besides me ever wants to use it, I am happy to provide documentation.