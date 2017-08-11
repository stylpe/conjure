class Conjure < Formula
  desc "Conjure: The Automated Constraint Modelling Tool"
  homepage "https://conjure.readthedocs.io/en/latest/welcome.html"
  url "https://github.com/conjure-cp/conjure/archive/v2.0.0.tar.gz"
  version "2.0.0"
  sha256 "20ca595cfd539644c714fe401b366f995ef14e2e137212f8d8f982a10daf6ff2"

  depends_on "haskell-stack" => :build

  def install
    system "cp", "etc/hs-deps/stack-8.0.yaml", "stack.yaml"
    system "stack", "setup"
    system "bash", "etc/build/version.sh"
    system "stack", "runhaskell", "etc/build/gen_Operator.hs"
    system "stack", "runhaskell", "etc/build/gen_Expression.hs"
    system "stack", "install"
    system "rm", "stack.yaml"
  end

  test do
    system "#{bin}/conjure", "--version"
  end

  def caveats; <<-EOS.undent
    Make sure the conjure binary is in your PATH, its current location is #{bin}/conjure.

    Conjure uses Savile Row (and one of a number of solvers like Minion), so make sure those are also in your PATH.
    EOS
  end

end
