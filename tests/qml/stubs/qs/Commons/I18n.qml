pragma Singleton
import QtQuick

QtObject {
  property string formatLocale: "en-GB"
  function formatNumber(value) { return String(value) }
}
