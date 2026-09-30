import sys

import pyslam.config as config

import numpy as np
import gtsam
import gtsam_factors

import unittest
from unittest import TestCase


# Checks the analytic Jacobian of gtsam_factors.PriorFactorSimilarity3 against a Richardson-extrapolated
# central-difference Jacobian of its error w.r.t. GTSAM's retraction (x.retract(d) = x * Exp(d)),
# including arbitrary (monocular) scales and very small/large translations.


def random_sim3(rng, rot, trans, log_scale):
    w = rng.normal(size=3)
    w = w / np.linalg.norm(w) * rot
    return gtsam.Similarity3(gtsam.Rot3.Expmap(w), rng.normal(size=3) * trans, float(np.exp(log_scale)))


def unwhitened_error(factor, x):
    # The factors use a unit-sigma noise model, so the linearized right-hand side is -e(x).
    values = gtsam.Values()
    values.insert(1, x)
    _, b = factor.linearize(values).jacobian()
    return -b


def reference_jacobian(factor, x, h=1e-3):
    def central(step):
        J = np.zeros((7, 7))
        for i in range(7):
            d = np.zeros(7)
            d[i] = step
            J[:, i] = (unwhitened_error(factor, x.retract(d)) - unwhitened_error(factor, x.retract(-d))) / (2 * step)
        return J

    return (4.0 * central(h / 2) - central(h)) / 3.0  # O(h^4)


class TestSim3PriorJacobian(TestCase):
    # (relative rotation angle, translation magnitude, relative log-scale)
    regimes = {
        "typical": (1.0, 1.0, 0.5),
        "large rotation": (3.0, 1.0, 0.5),
        "scale 1e-4": (1.0, 1.0, np.log(1e-4)),
        "scale 1e4": (1.0, 1.0, np.log(1e4)),
        "tiny translation": (1.0, 1e-9, 0.5),
        "huge translation and scale": (1.0, 1e6, np.log(1e4)),
        "at the prior": (0.0, 0.0, 0.0),
    }

    def test_jacobian_matches_finite_differences(self):
        rng = np.random.default_rng(0)
        noise = gtsam.noiseModel.Isotropic.Sigma(7, 1.0)
        for name, (rot, trans, log_scale) in self.regimes.items():
            with self.subTest(regime=name):
                for _ in range(20):
                    prior = random_sim3(rng, 0.7, 1.0, 0.3 * rng.normal())
                    x = prior.compose(random_sim3(rng, rot, trans, log_scale))
                    factor = gtsam_factors.PriorFactorSimilarity3(1, prior, noise)
                    values = gtsam.Values()
                    values.insert(1, x)
                    A, _ = factor.linearize(values).jacobian()
                    J_ref = reference_jacobian(factor, x)
                    rel_err = np.abs(A - J_ref).max() / max(1.0, np.abs(J_ref).max())
                    self.assertLess(rel_err, 1e-9, f"{name}: relative Jacobian error {rel_err:.2e}")

    def test_error_is_log_of_relative_transform(self):
        rng = np.random.default_rng(1)
        prior, x = random_sim3(rng, 0.5, 1.0, 0.2), random_sim3(rng, 0.8, 2.0, -0.4)
        factor = gtsam_factors.PriorFactorSimilarity3(1, prior, gtsam.noiseModel.Isotropic.Sigma(7, 1.0))
        expected = gtsam.Similarity3.Logmap(prior.inverse().compose(x))
        np.testing.assert_allclose(unwhitened_error(factor, x), expected, atol=1e-12)

    def test_converges_from_far_away(self):
        rng = np.random.default_rng(2)
        prior = random_sim3(rng, 0.7, 1.0, np.log(20.0))
        graph = gtsam.NonlinearFactorGraph()
        graph.add(gtsam_factors.PriorFactorSimilarity3(1, prior, gtsam.noiseModel.Isotropic.Sigma(7, 0.1)))
        values = gtsam.Values()
        values.insert(1, prior.compose(random_sim3(rng, 2.5, 5.0, np.log(1e-3))))
        result = gtsam.LevenbergMarquardtOptimizer(graph, values).optimize()
        np.testing.assert_allclose(
            gtsam.Similarity3.Logmap(prior.inverse().compose(result.atSimilarity3(1))), np.zeros(7), atol=1e-8
        )


if __name__ == "__main__":
    unittest.main()
