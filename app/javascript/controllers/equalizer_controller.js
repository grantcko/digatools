import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="equalizer"
export default class extends Controller {
  connect() {
    const container = document.getElementById('equalizer-container');
    const downloadLink = document.createElement('a');

    // select auto equalizer form
    const eqForm = document.getElementById("equalize-form");
    // const eqFormSubmit = document.getElementById("eq-submit");
    const loader = document.getElementById("loader");

    // run fuction when user submits the form
    eqForm.addEventListener("submit", submit);

    function submit(event) {
      // add loader
      // send form data to server for eq processing + add link to the output file
      console.log("submitted");
      loader.style.display = 'block'
      event.preventDefault();
      const formData = new FormData(event.target);
      fetch("/equalize", {method: "POST", body: formData, headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content }})
      .then(function(response) {
        console.log("post request sent");
        console.log(response);
        if (!response.ok) throw new Error("Audio processing failed");
        return response.json();
      })
      .then(function(data) {
        // remove loader
        loader.style.display = 'none'
        console.log(`this is the output file name: ${data.output}`);
        downloadLink.textContent = `⬇️ ${data.output} ⬇️`;
        const url = new URL(window.location.href);
        const tool_id = String(url.pathname).match(/\/tools\/(\d+)/)[1]
        downloadLink.href = `/download/?file=${data.output}&id=${tool_id}`;
        console.log(`this is the download link: ${downloadLink}`);
        container.insertBefore(downloadLink, eqForm)
      }).catch(() => {
        loader.style.display = "none";
        downloadLink.textContent = "Audio processing failed";
        container.insertBefore(downloadLink, eqForm);
      });
    };
  }
}
