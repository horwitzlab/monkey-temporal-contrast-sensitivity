function params = LMTF_global_to_local_model(globalparams, rfx, rfy, model_mode)
% params = LMTF_global_to_local_model(globalparams, rfx, rfy, mode)
%
% Takes a vector of global parameters, and a location on the screen
% represented in degrees of visual angle, and an optional mode parameter.
% Returns a 13-element vector of model parameters that describes a
% threshold funnel in LMTF space at the specified location in the visual
% field.
%

if (nargin < 4 && length(globalparams) == 18)
    model_mode = 3;
end
[phi,r] = cart2pol(abs(rfx), rfy);
if (model_mode == 2) % rampy trough
    xi_lum = 10.^(globalparams(12)+globalparams(13)*r+globalparams(14)*r*cos(2*phi));
    xi_rg = 10.^(globalparams(15)+globalparams(16)*r+globalparams(17)*r*cos(2*phi));
    params = [xi_lum; globalparams(1:5); xi_rg; globalparams(6:11)];
elseif (model_mode == 3) % tilted rampy trough
    xi_lum = 10.^(globalparams(12)+globalparams(13)*r+globalparams(14)*r*sin(2*phi)+globalparams(15)*r*cos(2*phi));
    xi_rg =  10.^(globalparams(16)+globalparams(17)*r+globalparams(18)*r*cos(2*phi));
    params = [xi_lum; globalparams(1:5); xi_rg; globalparams(6:11)];
elseif (model_mode == 4) % double tilted rampy trough
    xi_lum = 10.^(globalparams(12)+globalparams(13)*r+globalparams(14)*r*sin(2*phi)+globalparams(15)*r*cos(2*phi));
    xi_rg =  10.^(globalparams(16)+globalparams(17)*r+globalparams(18)*r*sin(2*phi)+globalparams(19)*r*cos(2*phi));
    params = [xi_lum; globalparams(1:5); xi_rg; globalparams(6:11)];
elseif (model_mode == 5) % yoked double tilted rampy trough
    xi_lum = 10.^(globalparams(12)+globalparams(13)*r+globalparams(14)*r*sin(2*phi)+globalparams(15)*r*cos(2*phi));
    xi_rg =  10.^(globalparams(16)+globalparams(17)*r+globalparams(14)*r*sin(2*phi)+globalparams(18)*r*cos(2*phi));
    params = [xi_lum; globalparams(1:5); xi_rg; globalparams(6:11)];
end