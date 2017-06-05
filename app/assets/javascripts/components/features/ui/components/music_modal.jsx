import PropTypes from 'prop-types';
import { defineMessages, injectIntl, FormattedMessage } from 'react-intl';
import IconButton from '../../../components/icon_button';
import Button from '../../../components/button';

class MusicModal extends React.PureComponent {

  constructor (props, context) {
    super(props, context);
    this.handleUpload = this.handleUpload.bind(this);

    this.setMusicRef = this.setMusicRef.bind(this);
    this.setPictureRef = this.setPictureRef.bind(this);
    this.setTitleRef = this.setTitleRef.bind(this);
    this.setArtistRef = this.setArtistRef.bind(this);

    this.handleChoosePicture = this.handleChoosePicture.bind(this);
    this.handleOnSelectPicture = this.handleOnSelectPicture.bind(this);

    this.handleChangeCheckbox = this.handleChangeCheckbox.bind(this);
    this.state = {
      isClickedWaring: false,
      pictureURL: null
    }
  }

  handleUpload() {
    this.props.onUpload({
      title: this.titleElement.value,
      artist: this.artistElement.value,
      picture: this.pictureFileElement.files[0],
      music: this.props.music
    });
    this.props.onClose();
  }

  handleChoosePicture (e) {
    this.pictureFileElement.click();
  }

  handleOnSelectPicture (e) {
    Promise.resolve()
    .then(() => new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onloadend = () => resolve(reader.result);
      reader.readAsDataURL(this.pictureFileElement.files[0]);
    }))
    .then((url)=>{
      this.setState({
        pictureURL: `url(${url})`
      });
    });
  }

  handleChangeCheckbox (e) {
    this.setState({isClickedWaring: !this.state.isClickedWaring});
  }

  setMusicRef (c) {
    this.musicFileElement = c;
  }

  setPictureRef (c) {
    this.pictureFileElement = c;
  }

  setTitleRef (c) {
    this.titleElement = c;
  }

  setArtistRef (c) {
    this.artistElement = c;
  }

  render () {
    const { title, artist, intl } = this.props;

    return (
      <div className='modal-root__modal music-modal'>
        <div className='music-modal__container'>
          <div className="music-modal__artwork">
            {(()=>{
              if(this.state.pictureURL) {
                return (
                  <div className="music-modal__artwork-exist" style={{backgroundImage: this.state.pictureURL}} onClick={this.handleChoosePicture} />
                );
              }
              return (
                <div className="music-modal__artwork-none" onClick={this.handleChoosePicture} >
                  <IconButton icon='camera' title="Upload Album Art" />
                </div>
              );
            })()}
          </div>

          <div className="music-modal__metabox">
            <div>
              <input className="music-modal__title" placeholder="楽曲名を入力" ref={this.setTitleRef} value={title} />
            </div>
            <input className="music-modal__artist" placeholder="作者名を入力" ref={this.setArtistRef} value={artist} />

            <input type="file" name="music"   accept="audio/*" ref={this.setMusicRef} />
            <input type="file" name="picture" accept="image/*" ref={this.setPictureRef} onChange={this.handleOnSelectPicture} />
          </div>
        </div>

        <div className='music-modal__action-bar'>
          <div className="action-bar__checkarea">
            <label>
              <input type="checkbox" checked={this.state.isClickedWaring} onChange={this.handleChangeCheckbox} />
              あなた自身が作成したコンテンツです
            </label>
          </div>
          <Button disabled={!this.state.isClickedWaring} text="upload" onClick={this.handleUpload} />
        </div>
      </div>
    );
  }
}

MusicModal.contextTypes = {
  router: PropTypes.object
};

MusicModal.propTypes = {
  title: PropTypes.string.isRequired,
  artist: PropTypes.string.isRequired,
  music: PropTypes.object.isRequired,
  onUpload: PropTypes.func.isRequired,
  onClose: PropTypes.func.isRequired,
  intl: PropTypes.object.isRequired
};

export default injectIntl(MusicModal);
